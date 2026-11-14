import Foundation

/// Conservative, read-only Windows batch parser and Madeira handoff plan.
/// Never runs scripts, changes game files, or assumes a Madeira import API.
struct GameLaunchPlan {
    struct Entry: Identifiable {
        let id: String
        let label: String
        let value: String
    }
    let executable: String?
    let arguments: String
    let workingDirectory: String
    let environment: [Entry]
    let notes: [String]
    let confidence: String

    var preview: String {
        var lines = ["ANKER — MADEIRA LAUNCH PLAN", "Preview only. Original game files are unchanged.",
                     "EXE: " + (executable ?? "Not found"),
                     "Arguments: " + (arguments.isEmpty ? "(none)" : arguments),
                     "Working directory: " + workingDirectory,
                     "Confidence: " + confidence, "", "Environment (set manually if supported):"]
        lines += environment.isEmpty ? ["(none detected)"] : environment.map { $0.label + "=" + $0.value }
        lines += ["", "Checks and limitations:"] + notes.map { "- " + $0 }
        return lines.joined(separator: "\n")
    }

    static func build(root: URL, report: GameInspection) -> GameLaunchPlan {
        var notes: [String] = []
        var environment: [Entry] = []
        var hints: [(exe: String, args: String, dir: String, script: String)] = []
        let files = Set(report.candidates.map { $0.id.lowercased().replacingOccurrences(of: "\\", with: "/") })
        let rootPath = root.standardizedFileURL.path

        func resolve(_ raw: String, relativeTo directory: String) -> String? {
            var value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                .replacingOccurrences(of: "\\", with: "/")
            if value.contains("%") || value.contains("!") || value.contains("$") {
                notes.append("Unresolved variable in path: " + raw)
                return nil
            }
            if value.range(of: #"^[A-Za-z]:/"#, options: .regularExpression) != nil || value.hasPrefix("//") {
                notes.append("Absolute Windows path needs manual mapping: " + raw)
                return nil
            }
            if value.hasPrefix("/") { notes.append("Absolute path needs review: " + raw); return nil }
            if value.lowercased().hasPrefix("./") { value = String(value.dropFirst(2)) }
            let base = root.appendingPathComponent(directory, isDirectory: true).standardizedFileURL
            let target = base.appendingPathComponent(value).standardizedFileURL
            let full = target.path
            guard full.hasPrefix(rootPath + "/") else {
                notes.append("Path escapes game folder: " + raw)
                return nil
            }
            return String(full.dropFirst(rootPath.count + 1))
        }

        for script in report.scripts.prefix(30) {
            let url = root.appendingPathComponent(script)
            let parsed = BatchInspection.inspect(url, root: root)
            if let warning = parsed.warning { notes.append(script + ": " + warning) }
            let scriptDirectory = (script as NSString).deletingLastPathComponent
            var currentDirectory = scriptDirectory == "." ? "" : scriptDirectory
            for line in parsed.lines {
                let raw = line.command.trimmingCharacters(in: .whitespacesAndNewlines)
                let lower = raw.lowercased()
                if lower.hasPrefix("set ") && !lower.hasPrefix("set /") {
                    let body = String(raw.dropFirst(4)).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                    if let equals = body.firstIndex(of: "=") {
                        let key = String(body[..<equals]).trimmingCharacters(in: .whitespaces)
                        let value = String(body[body.index(after: equals)...])
                        if !key.isEmpty && !key.contains(" ") && environment.count < 80 {
                            environment.append(.init(id: script + ":" + key, label: key, value: value))
                        }
                    }
                }
                if lower.hasPrefix("cd ") || lower.hasPrefix("pushd ") {
                    var target = lower.hasPrefix("pushd ") ? String(raw.dropFirst(6)) : String(raw.dropFirst(3))
                    if target.lowercased().hasPrefix("/d ") { target = String(target.dropFirst(3)) }
                    if target.contains("%~dp0") {
                        target = target.replacingOccurrences(of: "%~dp0", with: "", options: .caseInsensitive)
                        currentDirectory = scriptDirectory == "." ? "" : scriptDirectory
                    }
                    if let dir = resolve(target, relativeTo: currentDirectory) {
                        let candidate = root.appendingPathComponent(dir)
                        var isDir: ObjCBool = false
                        if FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDir) && isDir.boolValue {
                            currentDirectory = dir
                        } else { notes.append("Working directory not found: " + target) }
                    }
                }
                if line.classification == "Potentially unsafe" || line.classification == "File modification" {
                    notes.append("Manual review required: " + script + " line " + String(line.id))
                }
                // Extract a literal EXE and trailing arguments; never interpret shell operators.
                if lower.contains(".exe") {
                    let pattern = #"(?i)(?:"([^"]+\.exe)"|([^\s"&|<>]+\.exe))"#
                    if let match = raw.range(of: pattern, options: .regularExpression) {
                        let token = String(raw[match]).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
                        if let relative = resolve(token, relativeTo: currentDirectory), files.contains(relative.lowercased()) {
                            let args = String(raw[match.upperBound...]).trimmingCharacters(in: .whitespaces)
                            if !args.contains("&") && !args.contains("|") && !args.contains(">") && !args.contains("<") {
                                hints.append((relative, args, currentDirectory, script))
                            } else { notes.append("Complex shell syntax needs review in " + script) }
                        }
                    }
                }
            }
        }

        let ranked = report.candidates.map { candidate -> (GameInspection.Candidate, Int) in
            let occurrences = hints.filter { $0.exe.caseInsensitiveCompare(candidate.id) == .orderedSame }.count
            return (candidate, candidate.score + min(occurrences, 3) * 70)
        }.sorted { $0.1 == $1.1 ? $0.0.name < $1.0.name : $0.1 > $1.1 }
        let selected = ranked.first?.0
        let hint = selected.flatMap { candidate in hints.first { $0.exe.caseInsensitiveCompare(candidate.id) == .orderedSame } }
        if let hint { notes.append("Launch hint from: " + hint.script) }
        if report.scripts.count > 30 { notes.append("Only the first 30 scripts were inspected") }
        if report.candidates.isEmpty { notes.append("No EXE found; import a fully installed game folder") }
        notes.append("Check Madeira's supported architecture and manually enter launch arguments or environment only where its UI supports them.")
        notes.append("No automatic Madeira configuration import is available; test the launch and inspect logs for game-specific tuning.")
        let dir = hint?.dir ?? selected.map { ($0.id as NSString).deletingLastPathComponent } ?? ""
        return .init(executable: selected?.id, arguments: hint?.args ?? "",
                     workingDirectory: dir == "." || dir.isEmpty ? "(game root)" : dir,
                     environment: environment, notes: Array(Set(notes)).sorted(),
                     confidence: hint == nil ? "Low — file ranking" : "Medium — script references selected EXE")
    }
}
