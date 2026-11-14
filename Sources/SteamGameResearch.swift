import Foundation

/// Steam Store metadata is evidence about PC requirements, not a Madeira compatibility test.
struct SteamGameResearch {
    struct Result: Identifiable {
        let id: Int
        let title: String
        let requirements: String
        let suggestions: [String]
        let confidence: String
        var url: URL? { URL(string: "https://store.steampowered.com/app/\(id)/") }
    }
    enum ResearchError: LocalizedError {
        case noMatch, ambiguous, unavailable
        var errorDescription: String? {
            switch self {
            case .noMatch: return "No matching Windows game was found on Steam."
            case .ambiguous: return "Steam returned multiple plausible matches. Verify the game title manually."
            case .unavailable: return "Steam data could not be loaded. Existing game files are unchanged."
            }
        }
    }
    private static func normalized(_ text: String) -> String {
        let cleaned = text.lowercased().replacingOccurrences(of: #"(?i)(complete edition|definitive edition|game of the year|goty|repack|portable|setup|installer)"#, with: "", options: .regularExpression)
        return cleaned.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }.joined(separator: " ")
    }
    static func lookup(title: String, architecture: String) async throws -> Result {
        let query = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { throw ResearchError.noMatch }
        var url = URLComponents(string: "https://store.steampowered.com/api/storesearch/")!
        url.queryItems = [URLQueryItem(name: "term", value: query), URLQueryItem(name: "l", value: "english"), URLQueryItem(name: "cc", value: "US")]
        var request = URLRequest(url: url.url!)
        request.timeoutInterval = 15
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let search = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = search["items"] as? [[String: Any]] else { throw ResearchError.unavailable }
        let exact = items.filter {
            ($0["type"] as? String == "app") &&
            normalized($0["name"] as? String ?? "") == normalized(query)
        }
        guard exact.count == 1, let item = exact.first,
              let appid = item["id"] as? Int else {
            throw exact.isEmpty ? ResearchError.noMatch : ResearchError.ambiguous
        }
        var detailsURL = URLComponents(string: "https://store.steampowered.com/api/appdetails")!
        detailsURL.queryItems = [URLQueryItem(name: "appids", value: String(appid)),
                                 URLQueryItem(name: "l", value: "english"),
                                 URLQueryItem(name: "cc", value: "US")]
        var detailsRequest = URLRequest(url: detailsURL.url!)
        detailsRequest.timeoutInterval = 15
        let (detailsData, _) = try await URLSession.shared.data(for: detailsRequest)
        guard let root = try JSONSerialization.jsonObject(with: detailsData) as? [String: Any],
              let envelope = root[String(appid)] as? [String: Any],
              envelope["success"] as? Bool == true,
              let details = envelope["data"] as? [String: Any],
              let platforms = details["platforms"] as? [String: Any],
              platforms["windows"] as? Bool == true else { throw ResearchError.unavailable }
        let requirements = details["pc_requirements"] as? [String: Any] ?? [:]
        let minimum = requirements["minimum"] as? String ?? "Not published"
        let recommended = requirements["recommended"] as? String ?? ""
        let plain = (minimum + " " + recommended)
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
        var notes = ["Steam lists Windows PC requirements, not Madeira compatibility or verified performance."]
        if plain.range(of: #"(?i)directx\s*(?:version\s*)?12"#, options: .regularExpression) != nil {
            notes.append("DirectX 12 appears in PC requirements. Review Madeira D3D12 support; do not auto-force a graphics API.")
        } else if plain.range(of: #"(?i)directx\s*(?:version\s*)?11"#, options: .regularExpression) != nil {
            notes.append("DirectX 11 appears in PC requirements. D3D11 may be worth testing if Madeira supports it.")
        } else if plain.range(of: #"(?i)directx\s*(?:version\s*)?9"#, options: .regularExpression) != nil {
            notes.append("DirectX 9 appears in PC requirements. D3D9 may be worth testing.")
        }
        notes.append("Executable architecture detected locally: " + architecture + ". Use the local PE header rather than Steam to set bits.")
        notes.append("Resolution, FPS and performance settings require device-specific testing; Steam requirements cannot establish optimal values.")
        return Result(id: appid, title: details["name"] as? String ?? query,
                      requirements: plain.trimmingCharacters(in: .whitespacesAndNewlines),
                      suggestions: notes, confidence: "Steam match: exact normalized title; Madeira settings: unverified")
    }
}
