import Foundation

struct ZIPEntryReport {
    static func inspect(_ url: URL) -> String {
        guard let f = try? FileHandle(forReadingFrom: url) else { return "ZIP entries: cannot open file" }
        defer { try? f.close() }
        func u16(_ a: [UInt8], _ p: Int) -> Int { Int(a[p]) | Int(a[p+1]) << 8 }
        func u32(_ a: [UInt8], _ p: Int) -> UInt64 { UInt64(u16(a,p)) | UInt64(u16(a,p+2)) << 16 }
        do {
            let size = try f.seekToEnd()
            let tailSize = Int(min(size, 65_557))
            try f.seek(toOffset: size - UInt64(tailSize))
            let tail = [UInt8](try f.readToEnd() ?? Data())
            guard tail.count >= 22 else { return "ZIP entries: no end record" }
            var end: Int? = nil
            for i in stride(from: tail.count - 22, through: 0, by: -1) {
                if tail[i...i+3].elementsEqual([0x50,0x4b,0x05,0x06]) && i + 22 + u16(tail,i+20) == tail.count {
                    end = i; break
                }
            }
            guard let e = end else { return "ZIP entries: invalid end record" }
            let expected = u16(tail,e+10)
            let directorySize = u32(tail,e+12)
            let directoryOffset = u32(tail,e+16)
            guard expected < 100_000, directorySize <= 16_777_216, directoryOffset <= size,
                  directorySize <= size - directoryOffset else { return "ZIP entries: unsupported central directory size/offset" }
            try f.seek(toOffset: directoryOffset)
            let cd = [UInt8](try f.read(upToCount: Int(directorySize)) ?? Data())
            var offset = 0
            var seen = 0
            var methods: [Int: Int] = [:]
            var encrypted = 0
            var badPaths = 0
            var badOffsets = 0
            var examples: [String] = []
            while seen < expected && offset + 46 <= cd.count {
                guard cd[offset...offset+3].elementsEqual([0x50,0x4b,0x01,0x02]) else { break }
                let flags = u16(cd,offset+8)
                let method = u16(cd,offset+10)
                let nameLength = u16(cd,offset+28)
                let extraLength = u16(cd,offset+30)
                let commentLength = u16(cd,offset+32)
                let localOffset = u32(cd,offset+42)
                let next = offset + 46 + nameLength + extraLength + commentLength
                guard next <= cd.count else { break }
                let nameData = Data(cd[(offset+46)..<(offset+46+nameLength)])
                let name = String(data: nameData, encoding: .utf8) ?? "<non-UTF8 name>"
                methods[method, default: 0] += 1
                if flags & 1 != 0 { encrypted += 1 }
                if name.hasPrefix("/") || name.split(separator: "/").contains("..") || name.contains("\\") { badPaths += 1 }
                if localOffset >= size { badOffsets += 1 }
                if examples.count < 8 && (method != 0 && method != 8 || flags & 1 != 0 || name.contains("..")) {
                    examples.append("Entry \(seen+1): \(name.prefix(100)), method=\(method), flags=\(flags)")
                }
                seen += 1
                offset = next
            }
            let methodSummary = methods.keys.sorted().map { "\($0):\(methods[$0]!)" }.joined(separator: ", ")
            return "ZIP entries parsed=\(seen)/\(expected); compression methods [\(methodSummary)]; encrypted=\(encrypted); suspicious paths=\(badPaths); invalid local offsets=\(badOffsets)." + (examples.isEmpty ? "" : "\n" + examples.joined(separator: "\n"))
        } catch { return "ZIP entries: \(error.localizedDescription)" }
    }
}
