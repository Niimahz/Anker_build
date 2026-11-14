import Foundation

struct ArchiveDiagnostics {
    static func describe(_ url: URL) -> String {
        let fm = FileManager.default
        guard let attrs = try? fm.attributesOfItem(atPath: url.path),
              let bytes = attrs[.size] as? NSNumber else {
            return "Cannot read file attributes; verify Files access."
        }
        let size = bytes.int64Value
        guard let handle = try? FileHandle(forReadingFrom: url) else {
            return "File cannot be opened. Check LiveContainer file access."
        }
        defer { try? handle.close() }
        let head = (try? handle.read(upToCount: 16)) ?? Data()
        let signature = head.prefix(8).map { String(format: "%02X", $0) }.joined(separator: " ")
        let prefix = Array(head.prefix(6))
        let zip = prefix.count >= 4 && prefix[0] == 0x50 && prefix[1] == 0x4B &&
            ((prefix[2] == 0x03 && prefix[3] == 0x04) ||
             (prefix[2] == 0x05 && prefix[3] == 0x06) ||
             (prefix[2] == 0x07 && prefix[3] == 0x08))
        let sevenZip = prefix.count >= 6 && prefix == [0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C]
        let rar = prefix.count >= 6 && prefix == [0x52, 0x61, 0x72, 0x21, 0x1A, 0x07]
        var result = "Size: \(size) bytes; signature: \(signature). "
        if zip { result += "ZIP header found." }
        else if sevenZip { result += "7z header found." }
        else if rar { result += "RAR header found." }
        else { result += "No ZIP/RAR/7z signature at file start; it may be a split archive, self-extracting file, or a mislabeled download." }
        if size < 1024 { result += " Warning: unusually small game archive." }
        if zip && size >= 22 {
            do {
                try handle.seek(toOffset: UInt64(max(0, size - 65_557)))
                let tail = (try handle.readToEnd()) ?? Data()
                let marker: [UInt8] = [0x50, 0x4B, 0x05, 0x06]
                let data = [UInt8](tail)
                let hasEOCD = data.count >= 4 && (0...(data.count - 4)).contains { index in
                    data[index] == marker[0] && data[index+1] == marker[1] &&
                    data[index+2] == marker[2] && data[index+3] == marker[3]
                }
                result += hasEOCD ? " ZIP end record found." : " ZIP end record missing: file may be incomplete, split, or malformed."
            } catch { result += " Cannot inspect ZIP end record." }
        }
        return result
    }
}
