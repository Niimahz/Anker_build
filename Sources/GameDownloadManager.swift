import Foundation

/// System-managed background downloader. Background delivery depends on iOS and app identity.
/// Progress depends on the remote server providing a Content-Length.
final class GameDownloadManager: NSObject, URLSessionDownloadDelegate {
    static let backgroundIdentifier = "com.ankergamebridge.app.downloads"
    static var backgroundCompletionHandler: (() -> Void)?
    static var activeManager: GameDownloadManager?
    static var backgroundManagers: [String: GameDownloadManager] = [:]
    private var session: URLSession!
    var onProgress: ((Int64, Int64) -> Void)?
    var onFinish: ((URL, URLResponse?) -> Void)?
    var onFailure: ((String) -> Void)?
    private var currentTask: URLSessionDownloadTask?
    private var finished = false
    private var paused = false
    var onResumeData: ((Data) -> Void)?
    var requestHeaders: [String: String] = [:]

    init(identifier: String = GameDownloadManager.backgroundIdentifier) {
        super.init()
        let config = URLSessionConfiguration.background(withIdentifier: identifier)
        config.sessionSendsLaunchEvents = true
        config.isDiscretionary = false
        config.timeoutIntervalForRequest = 90
        config.waitsForConnectivity = true
        session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
        Self.activeManager = self
        Self.backgroundManagers[identifier] = self
    }
    func start(_ url: URL) {
        finished = false
        var request = URLRequest(url: url)
        request.timeoutInterval = 90
        for (key, value) in requestHeaders { request.setValue(value, forHTTPHeaderField: key) }
        currentTask = session.downloadTask(with: request)
        currentTask?.resume()
    }
    func resume(_ data: Data) {
        finished = false
        paused = false
        currentTask = session.downloadTask(withResumeData: data)
        currentTask?.resume()
    }
    func pause() {
        paused = true
        currentTask?.cancel(byProducingResumeData: { [weak self] data in
            if let data { self?.onResumeData?(data) }
            else { self?.onFailure?("Server did not provide resumable download data") }
        })
    }
    func cancel() { currentTask?.cancel() }
    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        let completion = Self.backgroundCompletionHandler
        Self.backgroundCompletionHandler = nil
        DispatchQueue.main.async { completion?() }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        onProgress?(totalBytesWritten, totalBytesExpectedToWrite)
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        guard !finished else { return }
        if let response = downloadTask.response as? HTTPURLResponse,
           !(200...299).contains(response.statusCode) {
            finished = true
            onFailure?("Server returned HTTP \(response.statusCode)")
            return
        }
        if let response = downloadTask.response as? HTTPURLResponse {
            let mime = (response.mimeType ?? "").lowercased()
            if mime.contains("text/html") || mime.contains("application/json") {
                finished = true
                onFailure?("The link returned a web page (HTTP \(response.statusCode)), not an archive. Use the download button in Browse to preserve verification cookies.")
                return
            }
        }
        // The system deletes its temporary download after this delegate returns.
        // Stage it synchronously before handing it to the UI.
        let staged = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        do {
            try FileManager.default.moveItem(at: location, to: staged)
            finished = true
            if let onFinish {
                onFinish(staged, downloadTask.response)
            } else {
                let downloads = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("Downloads", isDirectory: true)
                try FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
                let suggested = downloadTask.response?.suggestedFilename ?? downloadTask.originalRequest?.url?.lastPathComponent ?? "background-download"
                let name = URL(fileURLWithPath: suggested).lastPathComponent
                let destination = downloads.appendingPathComponent(UUID().uuidString.prefix(8) + "-" + name)
                try FileManager.default.moveItem(at: staged, to: destination)
            }
        } catch {
            finished = true
            onFailure?("Cannot save downloaded file: \(error.localizedDescription)")
        }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    didCompleteWithError error: Error?) {
        if paused { return }
        if let error, !finished {
            let nsError = error as NSError
            if let resumeData = nsError.userInfo[NSURLSessionDownloadTaskResumeData] as? Data {
                onResumeData?(resumeData)
            }
            finished = true
            onFailure?(error.localizedDescription)
        }
    }
}
