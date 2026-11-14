import Foundation

/// Four concurrent HTTP byte-range downloads, with strict response validation.
/// Uses temporary files instead of holding multi-gigabyte archives in memory.
final class SegmentedGameDownloader {
    var onProgress: ((Int64, Int64) -> Void)?
    var onFinish: ((URL, URLResponse?) -> Void)?
    var onFailure: ((String) -> Void)?
    var onFallback: (() -> Void)?
    var onPaused: (() -> Void)?
    private let stateDirectory: URL
    private var task: Task<Void, Never>?
    private let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.httpMaximumConnectionsPerHost = 6
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        config.urlCache = nil
        config.waitsForConnectivity = true
        config.timeoutIntervalForRequest = 120
        return URLSession(configuration: config)
    }()
    private var cancelled = false
    init(stateDirectory: URL) { self.stateDirectory = stateDirectory }

    func start(_ url: URL) {
        cancelled = false
        task = Task {
            do {
                var probe = URLRequest(url: url)
                probe.setValue("bytes=0-0", forHTTPHeaderField: "Range")
                probe.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
                let (sample, response) = try await session.data(for: probe)
                guard let http = response as? HTTPURLResponse,
                      http.statusCode == 206,
                      sample.count == 1,
                      let range = http.value(forHTTPHeaderField: "Content-Range"),
                      range.hasPrefix("bytes 0-0/"),
                      let length = Int64(range.dropFirst("bytes 0-0/".count)),
                      length >= 8_388_608 else {
                    if !cancelled { onFallback?() }
                    return
                }
                let validator = http.value(forHTTPHeaderField: "ETag")
                let modified = http.value(forHTTPHeaderField: "Last-Modified")
                // Only retain completed segments if the server supplies a stable validator.
                guard validator != nil || modified != nil else {
                    if !cancelled { onFallback?() }
                    return
                }
                let folder = stateDirectory
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let identity = "\(url.absoluteString)|\(length)|\(validator ?? "")|\(modified ?? "")"
                let metadata = folder.appendingPathComponent("identity")
                if let old = try? String(contentsOf: metadata, encoding: .utf8), old != identity {
                    for file in (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [] {
                        try? FileManager.default.removeItem(at: file)
                    }
                }
                try identity.write(to: metadata, atomically: true, encoding: .utf8)
                let count: Int64 = 4
                let chunk = length / count
                var completed: Int64 = 0
                let existing = (0..<Int(count)).compactMap { index -> (Int, URL, Int64)? in
                    let start = Int64(index) * chunk
                    let end = index == Int(count) - 1 ? length - 1 : start + chunk - 1
                    let file = folder.appendingPathComponent("part-\(index)")
                    let size = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? NSNumber)?.int64Value
                    return size == end - start + 1 ? (index, file, end - start + 1) : nil
                }
                completed = existing.reduce(0) { $0 + $1.2 }
                onProgress?(completed, length)
                let results = try await withThrowingTaskGroup(of: (Int, URL, Int64).self) { group in
                    for index in 0..<Int(count) {
                        if existing.contains(where: { $0.0 == index }) { continue }
                        group.addTask {
                            let start = Int64(index) * chunk
                            let end = index == Int(count) - 1 ? length - 1 : start + chunk - 1
                            var request = URLRequest(url: url)
                            request.setValue("bytes=\(start)-\(end)", forHTTPHeaderField: "Range")
                            request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
                            if let validator { request.setValue(validator, forHTTPHeaderField: "If-Range") }
                            else if let modified { request.setValue(modified, forHTTPHeaderField: "If-Range") }
                            let (part, response) = try await self.session.download(for: request)
                            guard let http = response as? HTTPURLResponse,
                                  http.statusCode == 206,
                                  http.value(forHTTPHeaderField: "Content-Range") == "bytes \(start)-\(end)/\(length)" else {
                                throw NSError(domain: "SegmentedDownload", code: 1, userInfo: [NSLocalizedDescriptionKey: "Server did not honor byte ranges"])
                            }
                            let expected = end - start + 1
                            let actual = (try FileManager.default.attributesOfItem(atPath: part.path)[.size] as? NSNumber)?.int64Value ?? -1
                            guard actual == expected else {
                                throw NSError(domain: "SegmentedDownload", code: 2, userInfo: [NSLocalizedDescriptionKey: "Incomplete downloaded segment"])
                            }
                            let saved = folder.appendingPathComponent("part-\(index)")
                            try? FileManager.default.removeItem(at: saved)
                            try FileManager.default.moveItem(at: part, to: saved)
                            return (index, saved, expected)
                        }
                    }
                    var parts: [(Int, URL, Int64)] = existing
                    for try await part in group {
                        parts.append(part)
                        completed += part.2
                        onProgress?(completed, length)
                    }
                    return parts.sorted { $0.0 < $1.0 }
                }
                try Task.checkCancellation()
                let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                FileManager.default.createFile(atPath: output.path, contents: nil)
                do {
                    let writer = try FileHandle(forWritingTo: output)
                    defer { try? writer.close() }
                    for (_, part, _) in results {
                        let reader = try FileHandle(forReadingFrom: part)
                        defer { try? reader.close() }
                        while let data = try reader.read(upToCount: 4_194_304), !data.isEmpty {
                            try Task.checkCancellation()
                            try writer.write(contentsOf: data)
                        }
                    }
                    let actual = (try FileManager.default.attributesOfItem(atPath: output.path)[.size] as? NSNumber)?.int64Value ?? -1
                    guard actual == length else { throw NSError(domain: "SegmentedDownload", code: 3, userInfo: [NSLocalizedDescriptionKey: "Merged file size mismatch"]) }
                    if !cancelled {
                        try? FileManager.default.removeItem(at: folder)
                        onFinish?(output, response)
                    }
                    else { try? FileManager.default.removeItem(at: output) }
                } catch {
                    try? FileManager.default.removeItem(at: output)
                    throw error
                }
            } catch {
                if !cancelled { onFailure?(error.localizedDescription) }
            }
        }
    }
    func pause() {
        cancelled = true
        task?.cancel()
        session.invalidateAndCancel()
        onPaused?()
    }
    func cancel() {
        cancelled = true
        task?.cancel()
        session.invalidateAndCancel()
        try? FileManager.default.removeItem(at: stateDirectory)
    }
}
