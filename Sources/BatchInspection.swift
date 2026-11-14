import Foundation

/// Read-only Windows batch inspection. Never invokes a shell or executes commands.
struct BatchInspection {
    struct Line: Identifiable {
        let id: Int
        let command: String
        let explanation: String
        let classification: String
    }
    let path: String
    let lines: [Line]
    let warning: String?
    static func inspect(_ file: URL, root: URL) -> BatchInspection {
        let standardized = file.standardizedFileURL
        let base = root.standardizedFileURL.path + "/"
        guard standardized.path.hasPrefix(base), file.pathExtension.lowercased() == "bat" || file.pathExtension.lowercased() == "cmd" else {
            return .init(path: file.lastPathComponent, lines: [], warning: "Invalid batch file path")
        }
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: file.path),
              let size = attrs[.size] as? NSNumber, size.intValue <= 1_048_576,
              let data = try? Data(contentsOf: file) else {
            return .init(path: file.lastPathComponent, lines: [], warning: "Cannot read batch file or exceeds 1 MB")
        }
        let text = String(data: data, encoding: .utf8) ??
                   String(data: data, encoding: .windowsCP1252) ??
                   String(decoding: data, as: UTF8.self)
        var lines: [Line] = []
        for (index, raw) in text.components(separatedBy: .newlines).enumerated() {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.isEmpty { continue }
            let lower = line.lowercased()
            let classification: String
            let explanation: String
            if lower == "@echo off" || lower == "echo off" || lower == "pause" || lower.hasPrefix("rem ") || lower.hasPrefix("::") {
                classification = "Informational"
                explanation = "Console display or comment; does not prepare game files."
            } else if lower.hasPrefix("cd ") || lower.hasPrefix("cd /d ") || lower.hasPrefix("pushd ") {
                classification = "Working directory"
                explanation = "Changes the launch working directory; use the corresponding game folder in Playport/Madeira."
            } else if lower.hasPrefix("set ") || lower.hasPrefix("setlocal") {
                classification = "Environment"
                explanation = "Sets a Windows environment variable; may need an equivalent setting in the Windows runner."
            } else if lower.hasPrefix("start ") || lower.hasSuffix(".exe") || lower.contains(".exe ") || lower.hasPrefix("call ") {
                classification = "Launch command"
                explanation = "May identify the real launcher or a prerequisite. Inspect target and arguments; not executed on iOS."
            } else if ["copy ", "xcopy ", "move ", "ren ", "rename ", "mkdir ", "md "].contains(where: { lower.hasPrefix($0) }) {
                classification = "File modification"
                explanation = "Potential preparation step. Requires explicit review before any changes to files."
            } else if ["del ", "erase ", "rd ", "rmdir ", "reg ", "powershell", "curl ", "bitsadmin", "certutil", "format ", "shutdown", "taskkill"].contains(where: { lower.hasPrefix($0) }) {
                classification = "Potentially unsafe"
                explanation = "Can delete, modify system state, or run external commands. Never auto-executed."
            } else {
                classification = "Needs review"
                explanation = "Batch syntax or command not automatically interpreted."
            }
            lines.append(.init(id: index + 1, command: line, explanation: explanation, classification: classification))
            if lines.count >= 500 { break }
        }
        return .init(path: file.lastPathComponent, lines: lines, warning: lines.count == 500 ? "Showing first 500 commands only" : nil)
    }
}
