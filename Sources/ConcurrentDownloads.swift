import Foundation
import Combine

@MainActor
final class ConcurrentDownloads: ObservableObject {
    final class Job: Identifiable {
        let id = UUID()
        let url: URL
        let mode: String
        var state = "Queued"
        var received: Int64 = 0
        var expected: Int64 = -1
        var manager: GameDownloadManager?
        var segmented: SegmentedGameDownloader?
        var resumeData: Data?
        var savedFile: URL?
        init(url: URL, mode: String) { self.url = url; self.mode = mode }
    }

    @Published private(set) var jobs: [Job] = []
    @Published private(set) var revision = 0
    private let limit = 3
    private var activeCount: Int {
        jobs.filter { $0.state == "Downloading" || $0.state == "Connecting" }.count
    }
    private func changed() { revision += 1 }

    func add(_ link: String, mode: String) {
        guard let url = URL(string: link.trimmingCharacters(in: .whitespacesAndNewlines)),
              ["http", "https"].contains(url.scheme?.lowercased() ?? "") else { return }
        jobs.append(Job(url: url, mode: mode))
        changed()
        pump()
    }

    private func pump() {
        for job in jobs where job.state == "Queued" && activeCount < limit {
            start(job)
        }
    }

    private func start(_ job: Job) {
        job.state = "Connecting"
        changed()
        let folder = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Downloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let identifier = GameDownloadManager.backgroundIdentifier + "." + job.id.uuidString
        let manager = GameDownloadManager(identifier: identifier)
        job.manager = manager
        manager.onProgress = { [weak self, weak job] received, expected in
            Task { @MainActor in
                guard let self, let job, job.state == "Downloading" || job.state == "Connecting" else { return }
                job.state = "Downloading"
                job.received = received
                job.expected = expected
                self.changed()
            }
        }
        manager.onFinish = { [weak self, weak job] staged, response in
            Task { @MainActor in
                guard let self, let job else {
                    try? FileManager.default.removeItem(at: staged)
                    return
                }
                guard job.state != "Cancelled", self.jobs.contains(where: { $0.id == job.id }) else {
                    try? FileManager.default.removeItem(at: staged)
                    return
                }
                let suggested = response?.suggestedFilename ?? job.url.lastPathComponent
                let safe = URL(fileURLWithPath: suggested).lastPathComponent
                let name = safe.isEmpty ? "archive" : safe
                let target = folder.appendingPathComponent(job.id.uuidString.prefix(8) + "-" + name)
                do {
                    try FileManager.default.moveItem(at: staged, to: target)
                    job.savedFile = target
                    job.state = "Completed"
                } catch {
                    job.state = "Save failed: " + error.localizedDescription
                }
                job.manager = nil
                job.segmented = nil
                self.changed()
                self.pump()
            }
        }
        manager.onFailure = { [weak self, weak job] message in
            Task { @MainActor in
                guard let self, let job, job.state != "Paused" && job.state != "Cancelled",
                      self.jobs.contains(where: { $0.id == job.id }) else { return }
                job.state = "Failed: " + message
                job.manager = nil
                job.segmented = nil
                self.changed()
                self.pump()
            }
        }
        manager.onResumeData = { [weak self, weak job] data in
            Task { @MainActor in
                guard let self, let job else { return }
                guard job.state != "Cancelled", self.jobs.contains(where: { $0.id == job.id }) else { return }
                job.resumeData = data
                job.state = "Paused"
                job.manager = nil
                self.changed()
                self.pump()
            }
        }
        if job.mode == "fast" {
            let parts = folder.appendingPathComponent(".parts-" + job.id.uuidString, isDirectory: true)
            let segmented = SegmentedGameDownloader(stateDirectory: parts)
            job.segmented = segmented
            segmented.onProgress = manager.onProgress
            segmented.onFinish = manager.onFinish
            segmented.onFailure = manager.onFailure
            segmented.onPaused = { [weak self, weak job] in
                Task { @MainActor in
                    guard let self, let job else { return }
                    guard job.state != "Cancelled", self.jobs.contains(where: { $0.id == job.id }) else { return }
                    job.state = "Paused"
                    job.segmented = nil
                    job.manager = nil
                    self.changed()
                    self.pump()
                }
            }
            segmented.onFallback = { [weak job, weak manager] in
                Task { @MainActor in
                    guard let job, let manager, job.state != "Paused" && job.state != "Cancelled" else { return }
                    job.segmented = nil
                    manager.start(job.url)
                }
            }
            segmented.start(job.url)
        } else if let resumeData = job.resumeData {
            manager.resume(resumeData)
            job.resumeData = nil
        } else {
            manager.start(job.url)
        }
    }

    func pause(_ job: Job) {
        guard job.state == "Downloading" || job.state == "Connecting" else { return }
        job.state = "Paused"
        if let segmented = job.segmented {
            segmented.pause()
        } else {
            job.manager?.pause()
        }
        changed()
        pump()
    }

    func resume(_ job: Job) {
        guard job.state == "Paused" || job.state.hasPrefix("Failed:") else { return }
        job.state = "Queued"
        changed()
        pump()
    }

    func cancel(_ job: Job) {
        guard job.state != "Completed" && job.state != "Cancelled" else { return }
        job.state = "Cancelled"
        job.segmented?.cancel()
        job.manager?.cancel()
        job.segmented = nil
        job.manager = nil
        job.resumeData = nil
        try? FileManager.default.removeItem(at: downloadsFolder.appendingPathComponent(".parts-" + job.id.uuidString, isDirectory: true))
        changed()
        pump()
    }
    private var downloadsFolder: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Downloads", isDirectory: true)
    }

    @discardableResult
    func delete(_ job: Job) -> String? {
        guard jobs.contains(where: { $0.id == job.id }) else { return nil }
        if let file = job.savedFile, FileManager.default.fileExists(atPath: file.path) {
            do { try FileManager.default.removeItem(at: file) }
            catch { return error.localizedDescription }
        }
        if job.state == "Downloading" || job.state == "Connecting" || job.state == "Queued" {
            cancel(job)
        }
        job.segmented?.cancel()
        job.manager?.cancel()
        job.resumeData = nil
        let parts = downloadsFolder.appendingPathComponent(".parts-" + job.id.uuidString, isDirectory: true)
        try? FileManager.default.removeItem(at: parts)
        jobs.removeAll { $0.id == job.id }
        changed()
        pump()
        return nil
    }

}
