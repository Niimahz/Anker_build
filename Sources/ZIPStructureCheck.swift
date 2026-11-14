import Foundation

struct ZIPStructureCheck {
    static func inspect(_ url: URL) -> String {
        guard let file = try? FileHandle(forReadingFrom: url) else { return "ZIP structure: cannot open file." }
        defer { try? file.close() }
        do {
            let size = try file.seekToEnd()
            let tailSize = Int(min(size, 65_557))
            try file.seek(toOffset: size - UInt64(tailSize))
            let tail = [UInt8](try file.readToEnd() ?? Data())
            guard tail.count >= 22 else { return "ZIP structure: too small." }
            func u16(_ b: [UInt8], _ p: Int) -> UInt64 { UInt64(b[p]) | UInt64(b[p+1]) << 8 }
            func u32(_ b: [UInt8], _ p: Int) -> UInt64 { u16(b,p) | u16(b,p+2) << 16 }
            var end: Int? = nil
            for p in stride(from: tail.count - 22, through: 0, by: -1) {
                if tail[p] == 0x50 && tail[p+1] == 0x4b && tail[p+2] == 0x05 && tail[p+3] == 0x06 &&
                    p + 22 + Int(u16(tail,p+20)) == tail.count {
                    end = p
                    break
                }
            }
            guard let p = end else { return "ZIP structure: no valid end record with matching comment length." }
            let disk = u16(tail,p+4)
            let centralDisk = u16(tail,p+6)
            let entries = u16(tail,p+10)
            let centralSize = u32(tail,p+12)
            let centralOffset = u32(tail,p+16)
            let zip64 = entries == 0xffff || centralSize == 0xffff_ffff || centralOffset == 0xffff_ffff
            var info = "ZIP structure: entries=\(entries), central directory size=\(centralSize), offset=\(centralOffset), ZIP64 markers=\(zip64), disk=\(disk), central disk=\(centralDisk)."
            if disk != 0 || centralDisk != 0 { info += " WARNING: split/multi-disk ZIP detected." }
            if zip64 {
                info += " ZIP64 metadata required; classic offsets cannot validate this archive."
                return info
            }
            guard centralOffset <= size, centralSize <= size, centralOffset + centralSize <= size else {
                return info + " ERROR: central directory points outside file; archive may be truncated or split."
            }
            try file.seek(toOffset: centralOffset)
            let signature = [UInt8](try file.read(upToCount: 4) ?? Data())
            if signature == [0x50,0x4b,0x01,0x02] {
                info += " Central directory header verified."
            } else {
                info += " WARNING: central directory signature mismatch (possibly self-extracting/prefixed or damaged ZIP)."
            }
            return info
        } catch { return "ZIP structure check failed: \(error.localizedDescription)" }
    }
}
