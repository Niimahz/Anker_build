import Foundation

/// Edits only a uniquely matched game in an explicitly selected Madeira library.
/// Unknown fields (including touch layouts) are preserved.
enum MadeiraLibraryEditor {
    struct Match: Identifiable {
        let id: String
        let title: String
        let path: String
        let arguments: String
    }
    enum EditorError: LocalizedError {
        case invalidLibrary, noMatch, ambiguousMatch, invalidSelection, changedOnDisk
        var errorDescription: String? {
            switch self {
            case .invalidLibrary: return "This is not a supported Madeira library (version 1)."
            case .noMatch: return "No matching game found in the selected Madeira library."
            case .ambiguousMatch: return "More than one game matches. Nothing was changed."
            case .invalidSelection: return "Select madeira-library.json from Madeira's Documents folder."
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
                         path: path, arguments: entry["arguments"] as? String ?? "")
        }
    }

    /// Returns backup URL. Caller must confirm the preview before invoking.
    static func apply(url: URL, expectedData: Data, entryID: String, arguments: String) throws -> URL {
        let (current, _) = try read(url)
        guard current == expectedData else { throw EditorError.changedOnDisk }
        guard var library = try JSONSerialization.jsonObject(with: current) as? [String: Any],
              var entries = library["entries"] as? [[String: Any]] else { throw EditorError.invalidLibrary }
        let indices = entries.indices.filter { entries[$0]["id"] as? String == entryID }
        guard indices.count == 1 else { throw EditorError.ambiguousMatch }
        entries[indices[0]]["arguments"] = arguments
        library["entries"] = entries
        let output = try JSONSerialization.data(withJSONObject: library, options: [.prettyPrinted, .sortedKeys])
        let backup = url.deletingLastPathComponent().appendingPathComponent("madeira-library-backup-\(UUID().uuidString).json")
        try current.write(to: backup, options: [.atomic])
        do { try output.write(to: url, options: [.atomic]) }
        catch { throw error }
        return backup
    }
}
