import Foundation
import zstd

/// ZIP reader for the ZIP Zstandard compression method (93).
/// Streams each entry through a temporary file to avoid loading multi-GB archives into RAM.
enum ZstandardZIP {
    enum Failure: LocalizedError {
        case invalid(String)
        var errorDescription: String? {
            if case .invalid(let message) = self { return message }
            return "Invalid ZIP"
        }
    }

    private static func number(_ bytes: [UInt8], _ offset: Int, _ count: Int) -> UInt64 {
        (0..<count).reduce(UInt64(0)) { $0 | (UInt64(bytes[offset + $1]) << ($1 * 8)) }
    }
    private static func read(_ handle: FileHandle, at offset: UInt64, count: Int) throws -> [UInt8] {
        try handle.seek(toOffset: offset)
        let bytes = [UInt8](try handle.read(upToCount: count) ?? Data())
        guard bytes.count == count else { throw Failure.invalid("Truncated ZIP at offset \(offset)") }
        return bytes
    }
    private static func transfer(_ handle: FileHandle, from offset: UInt64, length: UInt64, into destination: URL) throws {
        try handle.seek(toOffset: offset)
        FileManager.default.createFile(atPath: destination.path, contents: nil)
        let output = try FileHandle(forWritingTo: destination)
        defer { try? output.close() }
        var remaining = length
        while remaining > 0 {
            let count = Int(min(remaining, 4_194_304))
            guard let chunk = try handle.read(upToCount: count), !chunk.isEmpty else {
                throw Failure.invalid("Truncated ZIP entry data")
            }
            try output.write(contentsOf: chunk)
            remaining -= UInt64(chunk.count)
        }
    }

    static func extract(_ source: URL, to root: URL) throws {
        let input = try FileHandle(forReadingFrom: source)
        defer { try? input.close() }
        let size = try input.seekToEnd()
        let tailSize = Int(min(size, 65_557))
        guard tailSize >= 22 else { throw Failure.invalid("Missing ZIP end record") }
        let tail = try read(input, at: size - UInt64(tailSize), count: tailSize)
        var end: Int? = nil
        for i in stride(from: tail.count - 22, through: 0, by: -1) {
            if number(tail, i, 4) == 0x06054b50 &&
               i + 22 + Int(number(tail, i + 20, 2)) == tail.count {
                end = i; break
            }
        }
        guard let e = end else { throw Failure.invalid("Invalid ZIP end record") }
        guard number(tail, e + 4, 2) == 0, number(tail, e + 6, 2) == 0 else {
            throw Failure.invalid("Multi-disk ZIP is unsupported")
        }
        var entryCount = number(tail, e + 10, 2)
        var directorySize = number(tail, e + 12, 4)
        var directoryOffset = number(tail, e + 16, 4)
        if entryCount == 65535 || directorySize == 0xffffffff || directoryOffset == 0xffffffff {
            let endAbsolute = size - UInt64(tailSize) + UInt64(e)
            guard endAbsolute >= 20 else { throw Failure.invalid("Missing ZIP64 locator") }
            let locator = try read(input, at: endAbsolute - 20, count: 20)
            guard number(locator, 0, 4) == 0x07064b50,
                  number(locator, 4, 4) == 0,
                  number(locator, 16, 4) == 1 else {
                throw Failure.invalid("Invalid ZIP64 locator or multi-disk ZIP")
            }
            let zip64Offset = number(locator, 8, 8)
            guard zip64Offset <= size, size - zip64Offset >= 56 else {
                throw Failure.invalid("Invalid ZIP64 end record offset")
            }
            let record = try read(input, at: zip64Offset, count: 56)
            guard number(record, 0, 4) == 0x06064b50,
                  number(record, 16, 4) == 0, number(record, 20, 4) == 0 else {
                throw Failure.invalid("Invalid ZIP64 end record")
            }
            entryCount = number(record, 32, 8)
            directorySize = number(record, 40, 8)
            directoryOffset = number(record, 48, 8)
        }
        guard entryCount <= 2_000_000, directorySize <= 128_000_000,
              directoryOffset <= size, directorySize <= size - directoryOffset else {
            throw Failure.invalid("ZIP central directory exceeds supported limits")
        }
        let entries = Int(entryCount)
        let central = try read(input, at: directoryOffset, count: Int(directorySize))
        var cursor = 0
        let manager = FileManager.default
        let rootPath = root.standardizedFileURL.path + "/"
        for index in 0..<entries {
            guard cursor + 46 <= central.count, number(central, cursor, 4) == 0x02014b50 else {
                throw Failure.invalid("Invalid central directory entry \(index + 1)")
            }
            let flags = number(central, cursor + 8, 2)
            let method = number(central, cursor + 10, 2)
            var compressed = number(central, cursor + 20, 4)
            var uncompressed = number(central, cursor + 24, 4)
            let nameSize = Int(number(central, cursor + 28, 2))
            let extraSize = Int(number(central, cursor + 30, 2))
            let commentSize = Int(number(central, cursor + 32, 2))
            var localOffset = number(central, cursor + 42, 4)
            let next = cursor + 46 + nameSize + extraSize + commentSize
            guard next <= central.count, flags & 1 == 0 else {
                throw Failure.invalid("Encrypted or truncated entry \(index + 1)")
            }
            if compressed == 0xffffffff || uncompressed == 0xffffffff || localOffset == 0xffffffff {
                var extraCursor = cursor + 46 + nameSize
                let extraEnd = extraCursor + extraSize
                var foundZIP64 = false
                while extraCursor + 4 <= extraEnd {
                    let kind = number(central, extraCursor, 2)
                    let length = Int(number(central, extraCursor + 2, 2))
                    extraCursor += 4
                    guard extraCursor + length <= extraEnd else {
                        throw Failure.invalid("Invalid ZIP extra field")
                    }
                    if kind == 0x0001 {
                        foundZIP64 = true
                        var pos = extraCursor
                        func readZIP64Value() throws -> UInt64 {
                            guard pos + 8 <= extraCursor + length else {
                                throw Failure.invalid("Truncated ZIP64 entry values")
                            }
                            defer { pos += 8 }
                            return number(central, pos, 8)
                        }
                        if uncompressed == 0xffffffff { uncompressed = try readZIP64Value() }
                        if compressed == 0xffffffff { compressed = try readZIP64Value() }
                        if localOffset == 0xffffffff { localOffset = try readZIP64Value() }
                        break
                    }
                    extraCursor += length
                }
                guard foundZIP64 else { throw Failure.invalid("Missing ZIP64 entry field") }
            }
            let nameBytes = Data(central[(cursor + 46)..<(cursor + 46 + nameSize)])
            guard let name = String(data: nameBytes, encoding: .utf8),
                  !name.isEmpty, !name.hasPrefix("/"), !name.contains("\\"),
                  !name.split(separator: "/").contains("..") else {
                throw Failure.invalid("Unsafe or unsupported ZIP filename at entry \(index + 1)")
            }
            // Reject traversal and Windows-style absolute/drive paths before writing.
            // No file-content inspection or arbitrary expanded-size cap is applied.
            let parts = name.split(separator: "/", omittingEmptySubsequences: true)
            guard !parts.isEmpty,
                  !name.hasPrefix("/"), !name.contains("\\\\"),
                  !name.contains("\\0"), !name.contains(":"),
                  !parts.contains(".."), !parts.contains(".") else {
                throw Failure.invalid("Unsafe ZIP entry path")
            }
            let target = root.appendingPathComponent(name).standardizedFileURL
            guard target.path.hasPrefix(rootPath) else { throw Failure.invalid("Unsafe entry path") }
            // An earlier archive entry must not create a symlink that later entries follow.
            // Only directories and regular files are created by this extractor.
            let isDirectory = name.hasSuffix("/")
            if isDirectory {
                try manager.createDirectory(at: target, withIntermediateDirectories: true)
            } else {
                // Never follow a pre-existing symlink or overwrite an earlier entry.
                guard !manager.fileExists(atPath: target.path) else {
                    throw Failure.invalid("Duplicate ZIP destination: \\(name)")
                }
                guard method == 0 || method == 93 else {
                    throw Failure.invalid("Unsupported ZIP compression method \(method) in \(name)")
                }
                let header = try read(input, at: localOffset, count: 30)
                guard number(header, 0, 4) == 0x04034b50 else {
                    throw Failure.invalid("Missing local header for \(name)")
                }
                let payloadOffset = localOffset + 30 +
                    number(header, 26, 2) + number(header, 28, 2)
                guard payloadOffset <= size, compressed <= size - payloadOffset else {
                    throw Failure.invalid("Invalid compressed size for \(name)")
                }
                try manager.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
                if method == 0 {
                    guard compressed == uncompressed else {
                        throw Failure.invalid("Stored entry size mismatch: \(name)")
                    }
                    try transfer(input, from: payloadOffset, length: compressed, into: target)
                } else {
                    let temp = manager.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                    defer { try? manager.removeItem(at: temp) }
                    try transfer(input, from: payloadOffset, length: compressed, into: temp)
                    guard let src = InputStream(url: temp), let dst = OutputStream(url: target, append: false) else {
                        throw Failure.invalid("Cannot open stream for \(name)")
                    }
                    try ZStd.decompress(src: src, dst: dst)
                    let actual = (try manager.attributesOfItem(atPath: target.path)[.size] as? NSNumber)?.uint64Value ?? 0
                    guard actual == uncompressed else {
                        throw Failure.invalid("Decompressed size mismatch for \(name)")
                    }
                }
            }
            cursor = next
        }
    }
}
