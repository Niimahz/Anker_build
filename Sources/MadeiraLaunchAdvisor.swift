import Foundation

/// Offline, read-only launch guidance based on files actually present in a game folder.
/// These are diagnostics and hypotheses, not verified Madeira configuration values.
struct MadeiraLaunchAdvisor {
    struct Advice: Identifiable {
        let id: String
        let title: String
        let detail: String
        let confidence: String
    }
    let items: [Advice]

    static func inspect(root: URL, report: GameInspection) -> MadeiraLaunchAdvisor {
        var items: [Advice] = []
        func add(_ id: String, _ title: String, _ detail: String, _ confidence: String) {
            items.append(.init(id: id, title: title, detail: detail, confidence: confidence))
        }

        guard let launcher = report.candidates.first else {
            add("missing", "No game executable detected", "Import an already-installed Windows game folder containing its main .exe. An installer or an archive by itself is not a runnable game folder.", "High")
            return .init(items: items)
        }
        add("exe", "Suggested executable", "Start by selecting \(launcher.name) in Madeira. This is a filename-based suggestion, not a verified launcher.", "Medium")
        add("arch", "Executable architecture", "\(launcher.architecture). Choose a Madeira Windows runtime capable of this architecture; an incompatible runtime can fail before the game opens.", "High")

        let path = root.appendingPathComponent(launcher.id)
        add("directory", "Working directory", "Keep the original folder hierarchy and game data alongside the executable. If Madeira supports setting a working directory, use the folder containing \(path.lastPathComponent).", "Medium")

        var batchLaunch: [String] = []
        var batchEnvironment = false
        var batchModifications = false
        for relative in report.scripts.prefix(20) {
            let result = BatchInspection.inspect(root.appendingPathComponent(relative), root: root)
            for line in result.lines {
                if line.classification == "Launch command" && batchLaunch.count < 5 {
                    batchLaunch.append("\(relative): \(line.command)")
                }
                if line.classification == "Environment" || line.classification == "Working directory" { batchEnvironment = true }
                if line.classification == "File modification" || line.classification == "Potentially unsafe" { batchModifications = true }
            }
        }
        if !batchLaunch.isEmpty {
            add("batchlaunch", "BAT/CMD launch hints", "The scripts reference these launch commands:\n" + batchLaunch.joined(separator: "\n") + "\nCheck whether their target EXE or arguments differ from the suggested executable. Scripts are never executed.", "Medium")
        }
        if batchEnvironment {
            add("batchenv", "Script environment / paths", "A BAT/CMD script sets environment variables or changes directory. Review its commands and configure equivalent values manually only if Madeira supports them.", "High")
        }
        if batchModifications {
            add("batchunsafe", "Manual setup steps detected", "A BAT/CMD script may modify or delete files. Anker does not run these commands. Review each command before applying any legitimate setup step on a trusted Windows environment.", "High")
        }

        var hasDX9 = false
        var hasDX11 = false
        var hasDX12 = false
        var hasVC = false
        var hasUnity = false
        var hasUnreal = false
        var scanned = 0
        if let e = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) {
            while let u = e.nextObject() as? URL {
                scanned += 1
                if scanned > 100_000 { break }
                let n = u.lastPathComponent.lowercased()
                if n == "d3d9.dll" || n == "d3dx9_43.dll" { hasDX9 = true }
                if n == "d3d11.dll" || n == "dxgi.dll" { hasDX11 = true }
                if n == "d3d12.dll" || n == "d3d12core.dll" { hasDX12 = true }
                if n.hasPrefix("vcruntime") || n.hasPrefix("msvcp") { hasVC = true }
                if n == "unityplayer.dll" { hasUnity = true }
                if n == "engine" && u.hasDirectoryPath { hasUnreal = true }
            }
        }
        if hasDX12 {
            add("dx12", "Possible DirectX 12 dependency", "D3D12-related files were found. Verify that your Madeira build and chosen graphics backend support the game's required DirectX version. File presence alone does not prove the game requires DX12.", "Low")
        } else if hasDX11 {
            add("dx11", "Possible DirectX 11 dependency", "D3D11/DXGI-related files were found. If Madeira offers a DXVK/DirectX 11 compatibility option, test it; these files alone do not confirm the renderer.", "Low")
        } else if hasDX9 {
            add("dx9", "Possible DirectX 9 dependency", "D3D9-related files were found. Check Madeira's DirectX 9 compatibility options; this is only a clue from filenames.", "Low")
        }
        if hasVC {
            add("runtime", "Visual C++ runtime files", "Visual C++ runtime DLLs were detected. If the game reports a missing runtime or DLL, check Madeira's supported runtime components before changing any files.", "Medium")
        }
        if hasUnity || hasUnreal {
            add("engine", "Engine clues", hasUnity ? "UnityPlayer.dll suggests a Unity game." : "An Engine folder may indicate an Unreal-based game.", "Low")
        }
        add("baseline", "Safe first-launch checklist", "1. Keep all game files together.\n2. Select the suggested EXE and confirm architecture compatibility.\n3. Start with Madeira's default graphics settings.\n4. If launch fails, capture the exact error or game log.\n5. Change only one setting at a time; do not assume an unverified graphics backend will work.", "High")
        add("limits", "What this scan cannot determine", "This offline scan cannot verify Madeira's current supported renderers, optimal FPS settings, missing external dependencies, DRM status, or whether the game will launch. Those require Madeira documentation, device testing, and logs.", "High")
        return .init(items: items)
    }
}
