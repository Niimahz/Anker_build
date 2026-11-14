import Foundation

/// Repeated on-device measurements. A profile is eligible only when at least two
/// comparable successful runs were recorded for the same game and scene.
enum MadeiraBenchmark {
    struct Run: Codable, Identifiable {
        var id = UUID()
        var game: String
        var scene: String
        var profile: [String: String]
        var averageFPS: Double
        var lowFPS: Double
        var crashed: Bool
        var date = Date()
    }
    struct Ranked {
        let profile: [String: String]
        let runs: Int
        let averageFPS: Double
        let averageLowFPS: Double
        let crashes: Int
    }
    static let allowed = Set(["graphicsAPI", "resolution", "fpsMode", "performance", "reducedX87", "bits", "arguments"])
    static func store(_ run: Run) throws {
        guard run.averageFPS.isFinite, run.lowFPS.isFinite,
              run.averageFPS > 0, run.averageFPS <= 1000,
              run.lowFPS > 0, run.lowFPS <= run.averageFPS,
              !run.game.isEmpty, !run.scene.isEmpty,
              Set(run.profile.keys).isSubset(of: allowed) else {
            throw NSError(domain: "Anker.Benchmark", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid benchmark. FPS must be positive, and 1% low cannot exceed average FPS."])
        }
        var runs = load()
        runs.append(run)
        let data = try JSONEncoder().encode(Array(runs.suffix(500)))
        UserDefaults.standard.set(data, forKey: "anker.madeira.benchmarkRuns.v1")
    }
    static func load() -> [Run] {
        guard let data = UserDefaults.standard.data(forKey: "anker.madeira.benchmarkRuns.v1") else { return [] }
        return (try? JSONDecoder().decode([Run].self, from: data)) ?? []
    }
    static func ranking(game: String, scene: String) -> [Ranked] {
        let runs = load().filter { $0.game == game && $0.scene == scene }
        let groups = Dictionary(grouping: runs) { run in
            run.profile.keys.sorted().map { $0 + "=" + (run.profile[$0] ?? "") }.joined(separator: "|")
        }
        return groups.values.compactMap { group in
            let good = group.filter { !$0.crashed }
            guard good.count >= 2 else { return nil }
            return Ranked(profile: group[0].profile, runs: group.count,
                          averageFPS: good.map(\.averageFPS).reduce(0,+) / Double(good.count),
                          averageLowFPS: good.map(\.lowFPS).reduce(0,+) / Double(good.count),
                          crashes: group.count - good.count)
        }.sorted {
            if $0.crashes != $1.crashes { return $0.crashes < $1.crashes }
            if abs($0.averageLowFPS - $1.averageLowFPS) > 0.5 { return $0.averageLowFPS > $1.averageLowFPS }
            return $0.averageFPS > $1.averageFPS
        }
    }
    static func applicable(_ profile: [String: String]) -> [String: Any] {
        var changes: [String: Any] = [:]
        for (key, value) in profile where allowed.contains(key) {
            switch key {
            case "bits", "fpsMode":
                if let number = Int(value) { changes[key] = number }
            case "performance", "reducedX87":
                if value == "true" || value == "false" { changes[key] = value == "true" }
            default: changes[key] = value
            }
        }
        return changes
    }
}
