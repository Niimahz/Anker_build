import Foundation

struct GameInspection {
    struct Candidate: Identifiable {
        let id: String
        let name: String
        let architecture: String
        let score: Int
    }
    let candidates: [Candidate]
    let scripts: [String]
    let warnings: [String]
    let fileCount: Int
    var summary: String {
        if candidates.isEmpty { return "No Windows EXE found" }
        return "Suggested launcher: " + candidates[0].name + " (" + candidates[0].architecture + ")"
    }
    static func inspect(_ root: URL) -> GameInspection {
        let fm = FileManager.default
        guard let walk = fm.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles]) else {
            return .init(candidates: [], scripts: [], warnings: ["Unable to enumerate game directory"], fileCount: 0)
        }
        var exe: [Candidate] = []
        var bat: [String] = []
        var warnings: [String] = []
        var count = 0
        while let file = walk.nextObject() as? URL {
            count += 1
            if count > 150_000 { warnings.append("Scan truncated at 150,000 entries"); break }
            let ext = file.pathExtension.lowercased()
            let relative = String(file.path.dropFirst(root.path.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if ext == "bat" || ext == "cmd" { bat.append(relative) }
            guard ext == "exe" else { continue }
            let name = file.lastPathComponent.lowercased()
            let architecture = peArchitecture(file)
            var score = 0
            if name.contains("launcher") || name.contains("game") || name.contains("start") { score += 25 }
            if name.contains("setup") || name.contains("install") || name.contains("unins") || name.contains("redist") || name.contains("crash") { score -= 100 }
            if relative.components(separatedBy: "/").count <= 2 { score += 15 }
            if relative.lowercased().contains("redist") || relative.lowercased().contains("support") { score -= 70 }
            exe.append(.init(id: relative, name: relative, architecture: architecture, score: score))
        }
        exe.sort { $0.score == $1.score ? $0.name < $1.name : $0.score > $1.score }
        if !bat.isEmpty { warnings.append("Batch scripts detected. Review their commands on a Windows-compatible environment before launching; this app does not execute BAT files.") }
        if exe.contains(where: { $0.architecture == "Unknown" }) { warnings.append("Some EXE architectures could not be identified") }
        return .init(candidates: exe, scripts: bat.sorted(), warnings: warnings, fileCount: count)
    }
    private static func peArchitecture(_ url: URL) -> String {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return "Unknown" }
        defer { try? handle.close() }
        guard let header = try? handle.read(upToCount: 64), header.count >= 64,
              header[0] == 0x4d, header[1] == 0x5a else { return "Not a PE file" }
        let offset = Int(UInt32(header[0x3c]) | UInt32(header[0x3d]) << 8 | UInt32(header[0x3e]) << 16 | UInt32(header[0x3f]) << 24)
        guard offset >= 64, offset < 16_777_216 else { return "Unknown" }
        do {
            try handle.seek(toOffset: UInt64(offset))
            guard let pe = try handle.read(upToCount: 6), pe.count == 6,
                  Array(pe.prefix(4)) == [0x50, 0x45, 0, 0] else { return "Not a PE file" }
            let machine = UInt16(pe[4]) | UInt16(pe[5]) << 8
            switch machine {
            case 0x014c: return "Windows x86 (32-bit)"
            case 0x8664: return "Windows x64 (64-bit)"
            case 0xaa64: return "Windows ARM64"
            default: return String(format: "PE machine 0x%04X", machine)
            }
        } catch { return "Unknown" }
    }
}
