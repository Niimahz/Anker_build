import Foundation

/// Phase 2: read-only diagnostics from a user-selected Madeira run log.
/// Does not claim to benchmark FPS or alter controller/log preferences.
enum MadeiraRunDiagnostics {
    struct Result {
        let observations: [String]
        let suggestions: [String]
        let evidence: String
    }
    static func inspect(_ url: URL) throws -> Result {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let size = attributes[.size] as? NSNumber
        guard (size?.intValue ?? 0) <= 8_000_000 else {
            throw NSError(domain: "Anker.Diagnostics", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Log is over 8 MB. Export a shorter run log."])
        }
        let data = try Data(contentsOf: url)
        guard let log = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .utf16) else {
            throw NSError(domain: "Anker.Diagnostics", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Log text encoding not supported."])
        }
        let lower = log.lowercased()
        var observations: [String] = []
        var suggestions: [String] = []
        if lower.contains("out of memory") || lower.contains("allocation failed") || lower.contains("bad_alloc") {
            observations.append("Memory allocation failure reported.")
            suggestions.append("Test a lower in-game texture quality or resolution. Do not automatically change Madeira settings.")
        }
        if lower.contains("d3d12") && (lower.contains("failed") || lower.contains("error")) {
            observations.append("D3D12-related error appears in the log.")
            suggestions.append("Review the complete D3D12 error context and Madeira graphics backend before trying a different API.")
        }
        if lower.contains("vulkan") && (lower.contains("failed") || lower.contains("error")) {
            observations.append("Vulkan-related error appears in the log.")
            suggestions.append("Check Vulkan initialization and driver support before switching renderers.")
        }
        if lower.contains("unhandled exception") || lower.contains("segmentation fault") || lower.contains("access violation") {
            observations.append("Crash or unhandled exception reported.")
            suggestions.append("Compare the last successful startup and confirm game dependencies and architecture.")
        }
        if lower.contains("shader") && (lower.contains("compile") || lower.contains("cache")) {
            observations.append("Shader compilation/cache activity appears in the log.")
            suggestions.append("Compare a second run with the first; shader cache warm-up may explain intermittent stutter.")
        }
        if observations.isEmpty {
            observations.append("No recognized error signature detected. This does not prove the game is stable.")
            suggestions.append("Record FPS and frame-time during a repeatable 2-minute scene to establish a performance baseline.")
        }
        suggestions.append("Apply one tested change at a time, then compare logs and measured FPS. No automatic changes are made from keyword matches.")
        return Result(observations: observations, suggestions: suggestions,
                      evidence: "Read \(data.count) bytes from \(url.lastPathComponent). Log heuristics only; FPS not measured.")
    }
}
