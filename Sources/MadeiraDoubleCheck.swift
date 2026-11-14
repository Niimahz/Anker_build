import Foundation

/// Two independent evidence checks: Steam Windows listing and the actual local PE header.
/// A recommendation is never a measured Madeira performance result.
enum MadeiraDoubleCheck {
    struct Assessment {
        let checks: [String]
        let suggested: [String: String]
        let confidence: String
    }
    static func assess(steam: SteamGameResearch.Result, report: GameInspection, plan: GameLaunchPlan) -> Assessment {
        var checks = ["Steam game identified: \(steam.title) (App ID \(steam.id)).",
                      "Steam requirements are Windows PC requirements, not a Madeira benchmark.",
                      "Madeira compatibility and performance remain unverified until tested on-device."]
        var suggested: [String: String] = [:]
        if let path = plan.executable,
           let candidate = report.candidates.first(where: { $0.id.caseInsensitiveCompare(path) == .orderedSame }) {
            switch candidate.architecture {
            case "Windows x86 (32-bit)":
                suggested["bits"] = "32"
                checks.append("Local EXE PE header independently confirms 32-bit Windows architecture.")
            case "Windows x64 (64-bit)":
                suggested["bits"] = "64"
                checks.append("Local EXE PE header independently confirms 64-bit Windows architecture.")
            default:
                checks.append("EXE architecture is unknown or unsupported; architecture will not be changed.")
            }
        } else { checks.append("Launch EXE could not be independently matched; architecture stays unchanged.") }
        if !plan.arguments.isEmpty && plan.confidence.hasPrefix("Medium") {
            suggested["arguments"] = plan.arguments
            checks.append("Launch arguments cross-checked against an existing BAT/CMD launcher reference.")
        } else {
            checks.append("No reliable launcher arguments found; keep Madeira's existing arguments.")
        }
        checks.append("Graphics API: Steam DirectX version alone does not identify the actual renderer used by this executable.")
        checks.append("FPS, resolution, performance and reduced x87: preserve existing values until a Madeira session provides measured evidence.")
        return Assessment(checks: checks, suggested: suggested,
                          confidence: "Verified local file evidence + Steam identity; performance not benchmarked")
    }
}
