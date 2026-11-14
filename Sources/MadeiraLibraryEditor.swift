import Foundation

/// Edits only a uniquely matched game in an explicitly selected Madeira library.
/// Unknown fields (including touch layouts) are preserved.
enum MadeiraLibraryEditor {
    struct Match: Identifiable {
        let id: String
        let title: String
        let path: String
        let arguments: String
        let values: [String: Any]
    }
    enum EditorError: LocalizedError {
        case invalidLibrary, noMatch, ambiguousMatch, invalidSelection, changedOnDisk, invalidSettings
        var errorDescription: String? {
            switch self {
            case .invalidLibrary: return "This is not a supported Madeira library (version 1)."
            case .noMatch: return "No matching game found in the selected Madeira library."
            case .ambiguousMatch: return "More than one game matches. Nothing was changed."
            case .invalidSelection: return "Select madeira-library.json from Madeira's Documents folder."
            case .invalidSettings: return "One or more configuration values are invalid."
            case .changedOnDisk: return "The library changed since preview. Reopen it and review again."
            }
        }
    }

    static func read(_ url: URL) throws -> (Data, [[String: Any]]) {
        guard url.lastPathComponent == "madeira-library.json" else { throw EditorError.invalidSelection }
        let data = try Data(contentsOf: url)
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              object["version"] as? Int == 1,
              let entries = object["entries"] as? [[String: Any]] else { throw EditorError.invalidLibrary }
        return (data, entries)
    }

    static func matches(in entries: [[String: Any]], executable: String) -> [Match] {
        let normalized = executable.replacingOccurrences(of: "\\", with: "/").lowercased()
        return entries.compactMap { entry in
            guard let id = entry["id"] as? String,
                  let path = entry["relativePath"] as? String,
                  path.replacingOccurrences(of: "\\", with: "/").lowercased().hasSuffix("/" + normalized)
                    || path.replacingOccurrences(of: "\\", with: "/").lowercased() == normalized
            else { return nil }
            return Match(id: id, title: entry["title"] as? String ?? "Untitled",
                         path: path, arguments: entry["arguments"] as? String ?? "", values: entry)
        }
    }

    static let editableKeys: Set<String> = ["arguments", "bits", "graphicsAPI", "resolution", "fpsMode", "performance", "reducedX87"]
    static let protectedKeys: Set<String> = ["liveLogs", "touchControls", "controlLayout", "controlOpacity", "controlScale", "controls", "zones", "overlayFields", "display"]

    static func validate(_ changes: [String: Any]) throws {
        guard !changes.isEmpty, changes.keys.allSatisfy({ editableKeys.contains($0) }) else { throw EditorError.invalidSettings }
        for (key, value) in changes {
            switch key {
            case "arguments":
                guard let string = value as? String, string.count <= 4096 else { throw EditorError.invalidSettings }
            case "bits":
                guard let bits = value as? Int, [32, 64].contains(bits) else { throw EditorError.invalidSettings }
            case "graphicsAPI":
                guard let api = value as? String, ["D3D9", "D3D10", "D3D11", "D3D12", "Vulkan", "OpenGL"].contains(api) else { throw EditorError.invalidSettings }
            case "resolution":
                guard let resolution = value as? String,
                      resolution.range(of: #"^[0-9]{3,5}x[0-9]{3,5}$"#, options: .regularExpression) != nil
                else { throw EditorError.invalidSettings }
            case "fpsMode":
                guard let mode = value as? Int, (0...5).contains(mode) else { throw EditorError.invalidSettings }
            case "performance", "reducedX87":
                guard value is Bool else { throw EditorError.invalidSettings }
            default: throw EditorError.invalidSettings
            }
        }
    }

    /// Write only explicitly approved fields, preserving every other key.
    /// The caller must obtain security-scoped write access and show a diff first.
    static func apply(url: URL, expectedData: Data, entryID: String, changes: [String: Any]) throws -> URL {
        try validate(changes)
        let (current, _) = try read(url)
        guard current == expectedData else { throw EditorError.changedOnDisk }
        guard var library = try JSONSerialization.jsonObject(with: current) as? [String: Any],
              var entries = library["entries"] as? [[String: Any]] else { throw EditorError.invalidLibrary }
        let indices = entries.indices.filter { entries[$0]["id"] as? String == entryID }
        guard indices.count == 1 else { throw EditorError.ambiguousMatch }
        for (key, value) in changes { entries[indices[0]][key] = value }
        library["entries"] = entries
        let output = try JSONSerialization.data(withJSONObject: library, options: [.prettyPrinted, .sortedKeys])
        let backup = url.deletingLastPathComponent().appendingPathComponent("madeira-library-backup-\\(UUID().uuidString).json")
        try current.write(to: backup, options: [.atomic])
        try output.write(to: url, options: [.atomic])
        return backup
    }
}
