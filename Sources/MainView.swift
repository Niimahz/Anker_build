import SwiftUI
import WebKit
import UniformTypeIdentifiers
import ZIPFoundation
import LibArchive

final class BrowserNavigationState: ObservableObject {
    @Published var verificationDiagnostic = "Not inspected yet"
    @Published var canGoBack = false
    @Published var canGoForward = false
    weak var webView: WKWebView?
    weak var popup: WKWebView?
    @Published var browserDownloadProgress: Double = 0
    @Published var browserDownloadActive = false
    @Published var browserDownloadPaused = false
    @Published var browserDownloadBytes: Int64 = 0
    @Published var browserDownloadTotal: Int64 = -1
    var activeDownload: WKDownload?
    var downloadResumeData: Data?
    var downloadObserver: NSKeyValueObservation?
    func pauseBrowserDownload() {
        guard let activeDownload else { return }
        activeDownload.cancel { [weak self] data in
            DispatchQueue.main.async {
                guard let self else { return }
                self.downloadResumeData = data
                self.browserDownloadActive = false
                self.browserDownloadPaused = data != nil
                self.activeDownload = nil
                self.downloadObserver = nil
            }
        }
    }
    func resumeBrowserDownload() {
        guard let data = downloadResumeData, let webView else { return }
        downloadResumeData = nil
        browserDownloadPaused = false
        webView.resumeDownload(fromResumeData: data) { [weak self] download in
            guard let self else { return }
            download.delegate = self.browserDownloadDelegate
            self.browserDownloadDelegate?.observeDownload(download)
        }
    }
    weak var browserDownloadDelegate: Browser.Coordinator?
    func back() {
        if let popup { popup.removeFromSuperview(); self.popup = nil; sync(webView ?? popup); return }
        webView?.goBack()
    }
    func forward() { webView?.goForward() }
    func refresh() { webView?.reload() }
    func sync(_ web: WKWebView) {
        canGoBack = popup != nil || web.canGoBack
        canGoForward = web.canGoForward
    }
}

enum BrowserAdBlocking {
    static let blockedHosts: [String] = ["doubleclick.net","googlesyndication.com","googleadservices.com","adnxs.com","popads.net","propellerads.com","exoclick.com","trafficjunky.net","adsterra.com","popcash.net","onclicka.com","hilltopads.net","clickadu.com","juicyads.com","monetag.com"]
    static func isAdHost(_ host: String) -> Bool {
        let host = host.lowercased()
        return blockedHosts.contains { host == $0 || host.hasSuffix("." + $0) }
    }
    static let ruleJSON = #"[{"trigger":{"url-filter":"^https?://([^/]*\\.)?doubleclick\\.net([/:?]|$)"},"action":{"type":"block"}},{"trigger":{"url-filter":"^https?://([^/]*\\.)?googlesyndication\\.com([/:?]|$)"},"action":{"type":"block"}},{"trigger":{"url-filter":"^https?://([^/]*\\.)?googleadservices\\.com([/:?]|$)"},"action":{"type":"block"}},{"trigger":{"url-filter":"^https?://([^/]*\\.)?adnxs\\.com([/:?]|$)"},"action":{"type":"block"}},{"trigger":{"url-filter":"^https?://([^/]*\\.)?popads\\.net([/:?]|$)"},"action":{"type":"block"}},{"trigger":{"url-filter":"^https?://([^/]*\\.)?propellerads\\.com([/:?]|$)"},"action":{"type":"block"}},{"trigger":{"url-filter":"^https?://([^/]*\\.)?exoclick\\.com([/:?]|$)"},"action":{"type":"block"}},{"trigger":{"url-filter":"^https?://([^/]*\\.)?trafficjunky\\.net([/:?]|$)"},"action":{"type":"block"}},{"trigger":{"url-filter":"^https?://([^/]*\\.)?adsterra\\.com([/:?]|$)"},"action":{"type":"block"}},{"trigger":{"url-filter":"^https?://([^/]*\\.)?popcash\\.net([/:?]|$)"},"action":{"type":"block"}},{"trigger":{"url-filter":"^https?://([^/]*\\.)?onclicka\\.com([/:?]|$)"},"action":{"type":"block"}},{"trigger":{"url-filter":"^https?://([^/]*\\.)?hilltopads\\.net([/:?]|$)"},"action":{"type":"block"}},{"trigger":{"url-filter":"^https?://([^/]*\\.)?clickadu\\.com([/:?]|$)"},"action":{"type":"block"}},{"trigger":{"url-filter":"^https?://([^/]*\\.)?juicyads\\.com([/:?]|$)"},"action":{"type":"block"}},{"trigger":{"url-filter":"^https?://([^/]*\\.)?monetag\\.com([/:?]|$)"},"action":{"type":"block"}}]"#
    static func configure(_ web: WKWebView, enabled: Bool, reload: Bool, completion: (() -> Void)? = nil) {
        let controller = web.configuration.userContentController
        controller.removeAllContentRuleLists()
        guard enabled else { if reload { web.reload() }; completion?(); return }
        WKContentRuleListStore.default().compileContentRuleList(forIdentifier: "AnkerAdBlockV1", encodedContentRuleList: ruleJSON) { list, error in
            DispatchQueue.main.async {
                if let list { controller.add(list) }
                if let error { NSLog("AdBlock compilation error: %@", error.localizedDescription) }
                if reload { web.reload() }
                completion?()
            }
        }
    }
}

struct Browser: UIViewRepresentable {
    let address: String
    @Binding var currentPage: String
    @ObservedObject var navigation: BrowserNavigationState
    let adBlockEnabled: Bool
    let fastDownload: (URL) -> Bool
    func makeCoordinator() -> Coordinator { Coordinator(fastDownload: fastDownload, pageChanged: { currentPage = $0 }, navigation: navigation) }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default()
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.preferences.javaScriptCanOpenWindowsAutomatically = true
        let web = WKWebView(frame: .zero, configuration: config)
        web.allowsBackForwardNavigationGestures = true
        if #available(iOS 16.4, *) {
            web.isInspectable = true
        }
        navigation.webView = web
        BrowserAdBlocking.configure(web, enabled: adBlockEnabled, reload: false) {
            web.load(URLRequest(url: URL(string: address)!))
        }
        context.coordinator.adBlockEnabled = adBlockEnabled
        web.navigationDelegate = context.coordinator
        web.uiDelegate = context.coordinator
        return web
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        navigation.webView = uiView
        if context.coordinator.adBlockEnabled != adBlockEnabled {
            context.coordinator.adBlockEnabled = adBlockEnabled
            BrowserAdBlocking.configure(uiView, enabled: adBlockEnabled, reload: true)
        }
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate, WKDownloadDelegate {
        let fastDownload: (URL) -> Bool
        let pageChanged: (String) -> Void
        let navigation: BrowserNavigationState
        var adBlockEnabled = false
        func observeDownload(_ download: WKDownload) {
            navigation.activeDownload = download
            navigation.browserDownloadActive = true
            navigation.browserDownloadPaused = false
            navigation.browserDownloadProgress = 0
            navigation.downloadObserver = download.progress.observe(\.fractionCompleted, options: [.initial, .new]) { [weak navigation] progress, _ in
                DispatchQueue.main.async {
                    navigation?.browserDownloadProgress = progress.fractionCompleted
                    navigation?.browserDownloadBytes = progress.completedUnitCount
                    navigation?.browserDownloadTotal = progress.totalUnitCount
                }
            }
        }
        init(fastDownload: @escaping (URL) -> Bool, pageChanged: @escaping (String) -> Void, navigation: BrowserNavigationState) {
            self.navigation = navigation
            self.fastDownload = fastDownload
            self.pageChanged = pageChanged
            super.init()
            navigation.browserDownloadDelegate = self
        }
        func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
            webView.reload()
        }
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            NSLog("Anker WebKit navigation error: %@", error.localizedDescription)
        }
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            NSLog("Anker WebKit load error: %@", error.localizedDescription)
        }
        func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
            self.navigation.sync(webView)
        }
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            if webView === self.navigation.webView { self.navigation.sync(webView); inspectVerification(webView) }
            if webView === self.navigation.webView, let url = webView.url?.absoluteString {
                DispatchQueue.main.async { self.pageChanged(url) }
            }
        }

        private func inspectVerification(_ webView: WKWebView) {
            let js = """
            (() => {
              const frames = [...document.querySelectorAll("iframe")].filter(f => /cloudflare|turnstile/i.test(f.src || ""));
              const scripts = [...document.scripts].filter(s => /cloudflare|turnstile/i.test(s.src || ""));
              const widget = !!document.querySelector(".cf-turnstile, [data-sitekey], input[name=cf-turnstile-response]");
              const token = !!document.querySelector("input[name=cf-turnstile-response]")?.value;
              return JSON.stringify({host:location.hostname, frames:frames.length, scripts:scripts.length, widget, token, visibility:document.visibilityState});
            })()
            """
            webView.evaluateJavaScript(js) { [weak self] result, error in
                DispatchQueue.main.async {
                    self?.navigation.verificationDiagnostic = error?.localizedDescription ?? (result as? String) ?? "No result"
                }
            }
        }

        // Preserve the JavaScript opener relationship for verification popups.
        func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                     for navigationAction: WKNavigationAction,
                     windowFeatures: WKWindowFeatures) -> WKWebView? {
            let url = navigationAction.request.url
            if adBlockEnabled && BrowserAdBlocking.isAdHost(url?.host ?? "") { return nil }
            let host = (url?.host ?? "").lowercased()
            let challenge = host == "challenges.cloudflare.com" || host.hasSuffix(".cloudflare.com")
            let bootstrap = url == nil || url?.scheme == "about"
            guard navigationAction.navigationType == .linkActivated || challenge || bootstrap else { return nil }
            navigation.popup?.removeFromSuperview()
            let popup = WKWebView(frame: webView.bounds, configuration: configuration)
            popup.navigationDelegate = self
            popup.uiDelegate = self
            popup.translatesAutoresizingMaskIntoConstraints = false
            webView.addSubview(popup)
            navigation.popup = popup
            navigation.sync(webView)
            NSLayoutConstraint.activate([
                popup.leadingAnchor.constraint(equalTo: webView.leadingAnchor),
                popup.trailingAnchor.constraint(equalTo: webView.trailingAnchor),
                popup.topAnchor.constraint(equalTo: webView.topAnchor),
                popup.bottomAnchor.constraint(equalTo: webView.bottomAnchor)
            ])
            return popup
        }

        func webViewDidClose(_ webView: WKWebView) {
            if webView.superview is WKWebView {
                webView.removeFromSuperview()
                navigation.popup = nil
                if let main = navigation.webView { navigation.sync(main) }
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = navigationAction.request.url else {
                decisionHandler(.allow)
                return
            }
            let scheme = url.scheme?.lowercased() ?? ""
            if scheme == "about" { decisionHandler(.allow); return }
            guard scheme == "http" || scheme == "https" else {
                decisionHandler(.cancel)
                return
            }
            if adBlockEnabled && BrowserAdBlocking.isAdHost(url.host ?? "") {
                decisionHandler(.cancel)
                return
            }
            // WKWebView downloads preserve the browser session and redirects.
            if navigationAction.shouldPerformDownload {
                decisionHandler(.download)
            } else {
                decisionHandler(.allow)
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse,
                     decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
            let response = navigationResponse.response
            let attachment = (response as? HTTPURLResponse)?
                .value(forHTTPHeaderField: "Content-Disposition")?
                .lowercased().contains("attachment") == true
            let isFile = !navigationResponse.canShowMIMEType || attachment
            guard isFile else { decisionHandler(.allow); return }
            guard let url = response.url, ["http", "https"].contains(url.scheme?.lowercased() ?? "") else {
                decisionHandler(.download)
                return
            }
            // Keep verification cookies inside WKWebView during direct downloads.
            decisionHandler(.download)
        }

        func webView(_ webView: WKWebView, navigationAction: WKNavigationAction,
                     didBecome download: WKDownload) {
            download.delegate = self
            observeDownload(download)
            NotificationCenter.default.post(name: .gameBridgeBrowserDownloadStarted, object: nil)
        }
        func webView(_ webView: WKWebView, navigationResponse: WKNavigationResponse,
                     didBecome download: WKDownload) {
            download.delegate = self
            observeDownload(download)
            NotificationCenter.default.post(name: .gameBridgeBrowserDownloadStarted, object: nil)
        }
        func download(_ download: WKDownload, decideDestinationUsing response: URLResponse,
                      suggestedFilename: String, completionHandler: @escaping (URL?) -> Void) {
            let downloads = FileManager.default.defaultGameBridgeDocuments
                .appendingPathComponent("Downloads", isDirectory: true)
            try? FileManager.default.createDirectory(at: downloads, withIntermediateDirectories: true)
            let safe = URL(fileURLWithPath: suggestedFilename).lastPathComponent
            let destination = downloads.appendingPathComponent(UUID().uuidString.prefix(8) + "-" + safe)
            completionHandler(destination)
        }
        func downloadDidFinish(_ download: WKDownload) {
            navigation.browserDownloadActive = false
            navigation.activeDownload = nil
            navigation.downloadObserver = nil
            navigation.browserDownloadProgress = 1
            NotificationCenter.default.post(name: .gameBridgeBrowserDownloadFinished, object: nil)
        }
        func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
            navigation.browserDownloadActive = false
            navigation.activeDownload = nil
            navigation.downloadObserver = nil
            if let resumeData {
                navigation.downloadResumeData = resumeData
                navigation.browserDownloadPaused = true
            }
            NotificationCenter.default.post(name: .gameBridgeBrowserDownloadFailed, object: error.localizedDescription)
        }
    }
}

extension Notification.Name {
    static let gameBridgeBrowserDownloadStarted = Notification.Name("gameBridgeBrowserDownloadStarted")
    static let gameBridgeBrowserDownloadFinished = Notification.Name("gameBridgeBrowserDownloadFinished")
    static let gameBridgeBrowserDownloadFailed = Notification.Name("gameBridgeBrowserDownloadFailed")
}

@MainActor final class GameStore: ObservableObject {
    @Published var files: [URL] = []
    @Published var games: [URL] = []
    @Published var status = "Ready"
    @Published var diagnostic = ""
    @Published var extractedArchiveAwaitingDecision: URL?
    @Published var busy = false
    @Published var extracting = false
    @Published var extractionFileCount = 0
    @Published var extractionWrittenBytes: Int64 = 0
    @Published var extractionElapsedSeconds = 0
    @Published var downloading = false
    @Published var canResume = false
    @Published var downloadMode = "slow"
    private var resumeURL: URL { downloads.appendingPathComponent(".paused-download") }
    private var partsDirectory: URL { downloads.appendingPathComponent(".segmented-parts", isDirectory: true) }
    @Published var receivedBytes: Int64 = 0
    @Published var expectedBytes: Int64 = -1
    @Published var bytesPerSecond: Double = 0
    private var downloadManager: GameDownloadManager?
    private var segmentedDownloader: SegmentedGameDownloader?
    private var lastProgressTime = Date()
    private var lastProgressBytes: Int64 = 0
    var downloadFraction: Double? { expectedBytes > 0 ? min(1, Double(receivedBytes) / Double(expectedBytes)) : nil }
    func formatBytes(_ count: Int64) -> String { ByteCountFormatter.string(fromByteCount: count, countStyle: .file) }
    func pauseDownload() {
        if let segmentedDownloader { segmentedDownloader.pause() }
        else { downloadManager?.pause() }
    }
    func cancelDownload() {
        segmentedDownloader?.cancel()
        segmentedDownloader = nil
        downloadManager?.cancel()
        busy = false
        downloading = false
        canResume = false
        status = "Download cancelled"
    }
    func resumeDownload() {
        guard !busy,
              let saved = UserDefaults.standard.string(forKey: "pausedDownloadURL"),
              let url = URL(string: saved) else { return }
        let manager = GameDownloadManager()
        if FileManager.default.fileExists(atPath: partsDirectory.appendingPathComponent("identity").path) {
            startManager(manager, url: url, resumeData: nil, mode: "fast")
        } else if let data = try? Data(contentsOf: resumeURL) {
            startManager(manager, url: url, resumeData: data, mode: "slow")
        }
    }
    var documents: URL { FileManager.default.defaultGameBridgeDocuments }
    var downloads: URL { documents.appendingPathComponent("Downloads", isDirectory: true) }
    var library: URL { documents.appendingPathComponent("Games", isDirectory: true) }
    init() { refresh(); canResume = FileManager.default.fileExists(atPath: resumeURL.path) || FileManager.default.fileExists(atPath: partsDirectory.appendingPathComponent("identity").path) }
    var storagePath: String { documents.path }
    func refresh() {
        for dir in [downloads, library] { try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true) }
        files = ((try? FileManager.default.contentsOfDirectory(at: downloads, includingPropertiesForKeys: [.isDirectoryKey])) ?? []).filter { !$0.lastPathComponent.hasPrefix(".") }
        games = (try? FileManager.default.contentsOfDirectory(at: library, includingPropertiesForKeys: nil)) ?? []
    }
    func unique(_ target: URL) -> URL {
        if !FileManager.default.fileExists(atPath: target.path) { return target }
        let base = target.deletingPathExtension().lastPathComponent
        let ext = target.pathExtension
        for i in 2...9999 {
            let name = base + "-\(i)" + (ext.isEmpty ? "" : "." + ext)
            let candidate = target.deletingLastPathComponent().appendingPathComponent(name)
            if !FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        return target.deletingLastPathComponent().appendingPathComponent(UUID().uuidString)
    }
    func importItem(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            try FileManager.default.copyItem(at: url, to: unique(downloads.appendingPathComponent(url.lastPathComponent)))
            status = "Imported"; refresh()
        } catch { status = error.localizedDescription }
    }
    func download(_ string: String) {
        guard !busy else { return }
        guard let url = URL(string: string), ["https", "http"].contains(url.scheme?.lowercased() ?? "") else {
            status = "Enter a direct HTTP(S) file URL"; return
        }
        try? FileManager.default.removeItem(at: resumeURL)
        try? FileManager.default.removeItem(at: partsDirectory)
        canResume = false
        UserDefaults.standard.set(url.absoluteString, forKey: "pausedDownloadURL")
        startManager(GameDownloadManager(), url: url, resumeData: nil, mode: downloadMode)
    }
    private func startManager(_ manager: GameDownloadManager, url: URL, resumeData: Data?, mode: String) {
        busy = true
        downloading = true
        receivedBytes = 0
        expectedBytes = -1
        bytesPerSecond = 0
        lastProgressTime = Date()
        lastProgressBytes = 0
        status = "Connecting…"
        downloadManager = manager
        manager.onResumeData = { [weak self] data in
            Task { @MainActor [weak self] in
                guard let self else { return }
                do {
                    try data.write(to: self.resumeURL, options: .atomic)
                    self.canResume = true
                    self.status = "Download paused — ready to resume"
                } catch { self.status = "Cannot save resume data: " + error.localizedDescription }
                self.downloading = false
                self.busy = false
                self.downloadManager = nil
            }
        }
        manager.onProgress = { [weak self] received, expected in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let now = Date()
                let elapsed = now.timeIntervalSince(self.lastProgressTime)
                if elapsed >= 0.5 {
                    self.bytesPerSecond = max(0, Double(received - self.lastProgressBytes) / elapsed)
                    self.lastProgressTime = now
                    self.lastProgressBytes = received
                }
                self.receivedBytes = received
                self.expectedBytes = expected
                self.status = "Downloading…"
            }
        }
        manager.onFailure = { [weak self] message in
            Task { @MainActor [weak self] in
                self?.status = "Download failed: " + message
                self?.downloading = false
                self?.busy = false
                self?.downloadManager = nil
            }
        }
        manager.onFinish = { [weak self] staged, response in
            Task { @MainActor [weak self] in
                guard let self else { try? FileManager.default.removeItem(at: staged); return }
                let suggested = response?.suggestedFilename ?? url.lastPathComponent
                let safeName = URL(fileURLWithPath: suggested).lastPathComponent
                let name = safeName.isEmpty || safeName == "/" ? "download-" + UUID().uuidString : safeName
                let target = self.unique(self.downloads.appendingPathComponent(name))
                do {
                    try FileManager.default.moveItem(at: staged, to: target)
                    self.status = "Downloaded: " + target.lastPathComponent
                    self.refresh()
                } catch {
                    self.status = "Save failed: " + error.localizedDescription
                    try? FileManager.default.removeItem(at: staged)
                }
                self.downloading = false
                self.busy = false
                self.downloadManager = nil
                self.segmentedDownloader = nil
                self.canResume = false
                try? FileManager.default.removeItem(at: self.resumeURL)
                try? FileManager.default.removeItem(at: self.partsDirectory)
            }
        }
        if mode == "fast" && resumeData == nil {
            let segmented = SegmentedGameDownloader(stateDirectory: partsDirectory)
            segmentedDownloader = segmented
            segmented.onProgress = manager.onProgress
            segmented.onFinish = manager.onFinish
            segmented.onPaused = { [weak self] in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.segmentedDownloader = nil
                    self.canResume = true
                    self.busy = false
                    self.downloading = false
                    self.status = "Fast download paused — completed parts saved"
                }
            }
            segmented.onFailure = { [weak self] message in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.segmentedDownloader = nil
                    self.canResume = FileManager.default.fileExists(atPath: self.partsDirectory.appendingPathComponent("identity").path)
                    self.busy = false
                    self.downloading = false
                    self.status = "Fast download interrupted: " + message
                }
            }
            segmented.onFallback = { [weak self, weak manager] in
                Task { @MainActor [weak self, weak manager] in
                    guard let self, let manager, self.busy else { return }
                    self.segmentedDownloader = nil
                    self.status = "Fast unavailable; switching to background download"
                    manager.start(url)
                }
            }
            segmented.start(url)
        } else if let resumeData {
            manager.resume(resumeData)
        } else {
            manager.start(url)
        }
    }
    func keepExtractedArchive() { extractedArchiveAwaitingDecision = nil }
    func deleteExtractedArchive() {
        guard !busy, let archive = extractedArchiveAwaitingDecision else { return }
        extractedArchiveAwaitingDecision = nil
        guard archive.deletingLastPathComponent().standardizedFileURL == downloads.standardizedFileURL,
              FileManager.default.fileExists(atPath: archive.path) else {
            status = "Original archive is no longer in Downloads"
            return
        }
        do {
            try FileManager.default.removeItem(at: archive)
            status = "Original archive deleted; extracted game kept"
            refresh()
        } catch {
            status = "Could not delete archive: " + error.localizedDescription
        }
    }
    func prepare(_ url: URL) {
        guard !busy else { return }
        busy = true
        extracting = true
        extractionFileCount = 0
        extractionWrittenBytes = 0
        extractionElapsedSeconds = 0
        status = "Extracting \(url.lastPathComponent)…"
        diagnostic = ""
        let output = unique(library.appendingPathComponent(url.deletingPathExtension().lastPathComponent, isDirectory: true))
        let progressStore = self
        Task.detached(priority: .utility) { [weak progressStore] in
            let started = Date()
            while !Task.isCancelled {
                let isActive = await progressStore?.extracting ?? false
                if !isActive { break }
                let snapshot = Self.extractionSnapshot(in: output)
                let elapsed = Int(Date().timeIntervalSince(started))
                await MainActor.run { [weak progressStore] in
                    guard let progressStore, progressStore.extracting else { return }
                    progressStore.extractionFileCount = snapshot.0
                    progressStore.extractionWrittenBytes = snapshot.1
                    progressStore.extractionElapsedSeconds = elapsed
                }
                try? await Task.sleep(nanoseconds: 1_500_000_000)
            }
        }
        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                let isFolder = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
                if isFolder {
                    try FileManager.default.copyItem(at: url, to: output)
                } else {
                    let ext = url.pathExtension.lowercased()
                    guard ["zip", "rar", "7z", "tar", "gz", "tgz"].contains(ext) else {
                        throw NSError(domain: "AnkerGameBridge", code: 1, userInfo: [NSLocalizedDescriptionKey: "Unsupported archive. Import ZIP, RAR, 7z, TAR, or a game folder"])
                    }
                    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
                    if ext == "zip" {
                        let entryReport = ZIPEntryReport.inspect(url)
                        if entryReport.contains("93:") {
                            // ZIP method 93 is Zstandard: use bundled zstd decoder.
                            try ZstandardZIP.extract(url, to: output)
                        } else {
                            try FileManager.default.unzipItem(at: url, to: output)
                        }
                    } else {
                        try ArchiveReader().extract(url, to: output, permissionMode: .normalized)
                    }
                }
                await MainActor.run {
                    self?.diagnostic = ""
                    self?.status = "Prepared \(output.lastPathComponent)"
                    self?.busy = false
                    self?.extracting = false
                    self?.refresh()
                    if !isFolder {
                        self?.extractedArchiveAwaitingDecision = url
                    }
                }
            } catch {
                let details = ArchiveDiagnostics.describe(url) + (url.pathExtension.lowercased() == "zip" ? "\n" + ZIPStructureCheck.inspect(url) + "\n" + ZIPEntryReport.inspect(url) : "")
                try? FileManager.default.removeItem(at: output)
                await MainActor.run {
                    self?.diagnostic = details
                    self?.status = "Extraction failed (\(url.pathExtension.uppercased())): \(error.localizedDescription)"
                    self?.busy = false
                    self?.extracting = false
                }
            }
        }
    }
    nonisolated private static func extractionSnapshot(in folder: URL) -> (Int, Int64) {
        var count = 0
        var bytes: Int64 = 0
        if let enumerator = FileManager.default.enumerator(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: [.skipsHiddenFiles]
        ) {
            while let file = enumerator.nextObject() as? URL {
                guard let values = try? file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                      values.isRegularFile == true else { continue }
                count += 1
                bytes += Int64(values.fileSize ?? 0)
            }
        }
        return (count, bytes)
    }
    func executableCount(_ folder: URL) -> Int {
        guard let e = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: nil) else { return 0 }
        return e.compactMap { $0 as? URL }.filter { $0.pathExtension.lowercased() == "exe" }.count
    }
}

struct MainView: View {
    @StateObject private var store = GameStore()
    @StateObject private var concurrent = ConcurrentDownloads()
    @State private var showImporter = false
    @State private var directLink = ""
    @State private var browserDownloadStatus = ""
    @State private var pendingArchiveDeletion: URL?
    @State private var pendingGameFolderDeletion: URL?
    @State private var pendingQueueDeletion: UUID?
    @State private var selectedTab = 1
    private func browserBarButton(_ symbol: String, label: String, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .semibold))
                .frame(width: 48, height: 40)
        }
        .disabled(disabled)
        .accessibilityLabel(label)
    }
    @StateObject private var browserNavigation = BrowserNavigationState()
    @State private var browserAdBlockEnabled = true
    @State private var customWebsiteInput = ""
    @State private var customWebsiteURL = "https://www.google.com/"
    @State private var customWebsiteError = false
    @State private var customNavigationVersion = 0
    @State private var currentBrowserPage = "https://www.google.com/"
    private func addDownloadToQueue() {
        concurrent.add(directLink, mode: store.downloadMode)
        directLink = ""
    }
    private func openCustomWebsite() {
        let input = customWebsiteInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let candidate = input.contains("://") ? input : "https://" + input
        guard let url = URLComponents(string: candidate),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let host = url.host, host.contains("."), !host.hasPrefix("."), !host.hasSuffix(".") else {
            customWebsiteError = true
            return
        }
        customWebsiteError = false
        customWebsiteURL = candidate
        customNavigationVersion += 1
    }
    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack {
                VStack(spacing: 0) {
                    HStack(spacing: 8) {
                        Image(systemName: "globe").foregroundStyle(.green)
                        TextField("Enter website address", text: $customWebsiteInput)
                            .keyboardType(.URL)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.go)
                            .onSubmit { openCustomWebsite() }
                        Button("Go") { openCustomWebsite() }
                            .buttonStyle(.borderedProminent)
                    }
                    .padding(10)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    if customWebsiteError {
                        Text("Enter a valid HTTP or HTTPS website address.")
                            .font(.caption).foregroundStyle(.red)
                            .padding(.horizontal, 14)
                    }
                    Browser(address: customWebsiteURL,
                            currentPage: $currentBrowserPage,
                            navigation: browserNavigation,
                            adBlockEnabled: browserAdBlockEnabled,
                            fastDownload: { url in
                                guard store.downloadMode == "fast", !store.busy else { return false }
                                store.download(url.absoluteString)
                                return true
                            })
                        .id(customNavigationVersion)
                    HStack(spacing: 0) {
                        browserBarButton("chevron.left", label: "Back", disabled: !browserNavigation.canGoBack) { browserNavigation.back() }
                        browserBarButton("chevron.right", label: "Forward", disabled: !browserNavigation.canGoForward) { browserNavigation.forward() }
                        browserBarButton("arrow.clockwise", label: "Refresh") { browserNavigation.refresh() }
                        Spacer(minLength: 6)
                        Button {
                            UIPasteboard.general.string = browserNavigation.verificationDiagnostic
                        } label: {
                            Image(systemName: "doc.on.clipboard")
                                .font(.system(size: 17, weight: .medium))
                                .frame(width: 40, height: 40)
                        }
                        .accessibilityLabel("Copy verification diagnostic")
                        Button { browserAdBlockEnabled.toggle() } label: {
                            HStack(spacing: 5) {
                                Image(systemName: browserAdBlockEnabled ? "shield.checkered" : "shield.slash")
                                Text(browserAdBlockEnabled ? "On" : "Off")
                                    .font(.caption.weight(.semibold))
                            }
                            .foregroundStyle(browserAdBlockEnabled ? Color.green : Color.secondary)
                            .padding(.horizontal, 10)
                            .frame(height: 38)
                            .background(.green.opacity(browserAdBlockEnabled ? 0.12 : 0), in: Capsule())
                        }
                        .accessibilityLabel("Ad Block")
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(.regularMaterial)
                    .overlay(alignment: .top) { Divider() }
                }
                .navigationTitle("Web Browser")
                .navigationBarTitleDisplayMode(.inline)
            }
            .onReceive(NotificationCenter.default.publisher(for: .gameBridgeBrowserDownloadStarted)) { _ in
                browserDownloadStatus = "Browser download started — authenticated session"
                selectedTab = 1
            }
            .onReceive(NotificationCenter.default.publisher(for: .gameBridgeBrowserDownloadFinished)) { _ in
                browserDownloadStatus = "Browser download completed"
                store.refresh()
            }
            .onReceive(NotificationCenter.default.publisher(for: .gameBridgeBrowserDownloadFailed)) { event in
                browserDownloadStatus = "Browser download failed: " + ((event.object as? String) ?? "Unknown error")
            }
            .tabItem { Label("Browse", systemImage: "globe") }.tag(0)
            NavigationStack {
                List {
                    Section {
                        Label("Original archives stay in Files unless you choose to delete them after successful extraction. Prepared games remain in My Games.", systemImage: "externaldrive")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                    if !browserDownloadStatus.isEmpty || browserNavigation.browserDownloadActive || browserNavigation.browserDownloadPaused {
                        Section("Browser download") {
                            if !browserDownloadStatus.isEmpty {
                                Text(browserDownloadStatus).font(.subheadline)
                            }
                            if browserNavigation.browserDownloadActive {
                                if browserNavigation.browserDownloadTotal > 0 {
                                    ProgressView(value: browserNavigation.browserDownloadProgress)
                                    Text("\(Int(browserNavigation.browserDownloadProgress * 100))% · \(ByteCountFormatter.string(fromByteCount: browserNavigation.browserDownloadBytes, countStyle: .file)) / \(ByteCountFormatter.string(fromByteCount: browserNavigation.browserDownloadTotal, countStyle: .file))")
                                        .font(.caption.monospacedDigit())
                                } else {
                                    ProgressView()
                                    Text("Downloading · total size not reported").font(.caption)
                                }
                                Button("Pause browser download") { browserNavigation.pauseBrowserDownload() }
                            } else if browserNavigation.browserDownloadPaused {
                                Button("Resume browser download") { browserNavigation.resumeBrowserDownload() }
                            }
                        }
                    }
                    Section {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack(spacing: 10) {
                                Image(systemName: "arrow.down.to.line.compact")
                                    .font(.title2.bold())
                                    .foregroundStyle(.green)
                                    .frame(width: 44, height: 44)
                                    .background(.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 13))
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Download Center").font(.title3.bold())
                                    Text("Up to \(concurrent.limit) downloads at once").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            HStack(spacing: 8) {
                                Image(systemName: "link").foregroundStyle(.secondary)
                                TextField("Paste a direct file URL", text: $directLink)
                                    .keyboardType(.URL)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                                    .submitLabel(.go)
                                    .onSubmit { addDownloadToQueue() }
                                if !directLink.isEmpty {
                                    Button { directLink = "" } label: { Image(systemName: "xmark.circle.fill") }
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(12)
                            .background(Color.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
                            Picker("Simultaneous downloads", selection: Binding(get: { concurrent.limit }, set: { concurrent.setLimit($0) })) {
                                ForEach(1...4, id: \.self) { count in
                                    Text("\(count)").tag(count)
                                }
                            }
                            .pickerStyle(.segmented)
                            HStack(spacing: 10) {
                                Picker("Mode", selection: $store.downloadMode) {
                                    Text("Fast · 4 parts").tag("fast")
                                    Text("Reliable · Background").tag("slow")
                                }
                                .pickerStyle(.segmented)
                            }
                            Button { addDownloadToQueue() } label: {
                                Label("Add Download", systemImage: "plus.circle.fill")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 5)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.green)
                            .disabled(directLink.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            Text("For verified or protected links, tap Download inside Browse. A copied page URL may not be the file URL.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 6)
                    }
                    if !concurrent.jobs.isEmpty {
                        Section("Queue · \(concurrent.jobs.count)") {
                            ForEach(concurrent.jobs) { job in
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack(spacing: 10) {
                                        Image(systemName: job.state == "Completed" ? "checkmark.circle.fill" : "arrow.down.circle")
                                            .font(.title2)
                                            .foregroundStyle(job.state == "Completed" ? Color.green : Color.accentColor)
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(job.url.lastPathComponent.isEmpty ? (job.url.host ?? "Download") : job.url.lastPathComponent)
                                                .font(.subheadline.weight(.semibold))
                                                .lineLimit(2)
                                            Text(job.mode == "fast" && job.state == "Downloading" && job.received == 0 ? "Downloading 4 parts · progress updates as each part completes" : job.state)
                                                .font(.caption)
                                                .foregroundStyle(job.state.hasPrefix("Failed") ? Color.red : Color.secondary)
                                                .lineLimit(3)
                                        }
                                        Spacer()
                                        if job.expected > 0 {
                                            Text("\(Int(min(1, Double(job.received) / Double(job.expected)) * 100))%")
                                                .font(.subheadline.monospacedDigit().bold())
                                        }
                                    }
                                    if job.expected > 0 {
                                        ProgressView(value: min(1, Double(job.received) / Double(job.expected)))
                                            .tint(.green)
                                    } else if job.state == "Connecting" || job.state == "Downloading" {
                                        ProgressView()
                                    }
                                    if job.received > 0 {
                                        Text(ByteCountFormatter.string(fromByteCount: job.received, countStyle: .file) +
                                             (job.expected > 0 ? " / " + ByteCountFormatter.string(fromByteCount: job.expected, countStyle: .file) : " received"))
                                            .font(.caption.monospacedDigit())
                                            .foregroundStyle(.secondary)
                                    }
                                    HStack(spacing: 14) {
                                        if job.state == "Downloading" || job.state == "Connecting" {
                                            Button { concurrent.pause(job) } label: { Label("Pause", systemImage: "pause.fill") }
                                        } else if job.state == "Paused" || job.state.hasPrefix("Failed") {
                                            Button { concurrent.resume(job) } label: { Label("Retry", systemImage: "arrow.clockwise") }
                                        }
                                        if job.state != "Completed" && job.state != "Cancelled" {
                                            Button(role: .destructive) { concurrent.cancel(job) } label: { Label("Cancel", systemImage: "xmark") }
                                        }
                                    }
                                    .font(.caption.weight(.medium))
                                    .buttonStyle(.borderless)
                                    Button(role: .destructive) { pendingQueueDeletion = job.id } label: { Label("Delete", systemImage: "trash") }
                                        .font(.caption)
                                        .buttonStyle(.borderless)
                                }
                                .padding(.vertical, 7)
                            }
                        }
                    }
                    if store.canResume && !store.downloading {
                        Section("Previous paused transfer") {
                            Button("Resume previous download") { store.resumeDownload() }
                        }
                    }
                    Section("Archives · \(store.files.count)") {
                        ForEach(store.files, id: \.path) { url in
                            VStack(alignment: .leading, spacing: 10) {
                                Label {
                                    Text(url.lastPathComponent)
                                        .font(.headline)
                                        .lineLimit(3)
                                } icon: {
                                    Image(systemName: "doc.zipper")
                                        .foregroundStyle(.tint)
                                }
                                HStack {
                                    Text(url.pathExtension.uppercased())
                                    if let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) {
                                        Text("· " + store.formatBytes(Int64(size)))
                                    }
                                    Spacer()
                                }
                                .font(.caption).foregroundStyle(.secondary)
                                HStack {
                                    Button { store.prepare(url) } label: {
                                        Label("Extract game", systemImage: "shippingbox.and.arrow.backward")
                                    }
                                    .buttonStyle(.borderedProminent)
                                    .disabled(store.busy)
                                    Spacer()
                                    ShareLink(item: url) {
                                        Label("Share", systemImage: "square.and.arrow.up")
                                    }
                                    .buttonStyle(.bordered)
                                    Button(role: .destructive) { pendingArchiveDeletion = url } label: { Label("Delete file", systemImage: "trash") }
                                        .buttonStyle(.bordered)
                                }
                            }
                            .padding(.vertical, 5)
                        }
                    }
                    Section {
                        Button { showImporter = true } label: {
                            Label("Import archive or folder from Files", systemImage: "plus.circle.fill")
                        }
                        .disabled(store.busy)
                    }
                    Section("About & Legal") {
                        LabeledContent("Publisher", value: "Niimahz")
                        Link("Terms of Use", destination: URL(string: "https://github.com/Niimahz/Anker_build/blob/main/TERMS.md")!)
                        Link("Privacy Policy", destination: URL(string: "https://github.com/Niimahz/Anker_build/blob/main/PRIVACY.md")!)
                        Link("Copyright & Licenses", destination: URL(string: "https://github.com/Niimahz/Anker_build/blob/main/LICENSE")!)
                        Text("Only download and share content you have the right to use.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Section("Activity") {
                        HStack(alignment: .top) {
                            Image(systemName: store.busy ? "hourglass" : "checkmark.circle")
                                .foregroundStyle(store.busy ? .orange : .green)
                            Text(store.status).font(.subheadline).textSelection(.enabled)
                        }
                    }
                    if store.extracting {
                        Section("Extraction progress") {
                            ProgressView()
                            Text("\(store.extractionFileCount) files · \(ByteCountFormatter.string(fromByteCount: store.extractionWrittenBytes, countStyle: .file)) written")
                                .font(.caption.monospacedDigit())
                            Text("Elapsed: \(store.extractionElapsedSeconds / 60)m \(store.extractionElapsedSeconds % 60)s")
                                .font(.caption)
                            Text("Exact percentage is unavailable from this archive engine.")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                    if !store.diagnostic.isEmpty {
                        Section("Archive diagnostics") {
                            Text(store.diagnostic).font(.footnote).textSelection(.enabled)
                            Button("Copy diagnostics") { UIPasteboard.general.string = store.status + "\n" + store.diagnostic }
                        }
                    }
                }
                .confirmationDialog("Delete file from storage?", isPresented: Binding(get: { pendingArchiveDeletion != nil }, set: { if !$0 { pendingArchiveDeletion = nil } })) {
                    Button("Delete permanently", role: .destructive) {
                        if let file = pendingArchiveDeletion {
                            do { try FileManager.default.removeItem(at: file); store.refresh() }
                            catch { store.status = "Delete failed: " + error.localizedDescription }
                        }
                        pendingArchiveDeletion = nil
                    }
                } message: { Text("The original archive will be deleted. Extracted games remain.") }
                .confirmationDialog("Delete download?", isPresented: Binding(get: { pendingQueueDeletion != nil }, set: { if !$0 { pendingQueueDeletion = nil } })) {
                    Button("Delete entry and file", role: .destructive) {
                        if let id = pendingQueueDeletion, let job = concurrent.jobs.first(where: { $0.id == id }) {
                            if let error = concurrent.delete(job) { store.status = "Delete failed: " + error }
                            else { store.refresh() }
                        }
                        pendingQueueDeletion = nil
                    }
                } message: { Text("Deletes the completed file and temporary download parts when present.") }

                .navigationTitle("Anker Bridge")
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button { store.refresh() } label: { Image(systemName: "arrow.clockwise") }
                            .accessibilityLabel("Refresh files")
                    }
                }
                .refreshable { store.refresh() }
                .fileImporter(isPresented: $showImporter, allowedContentTypes: [.item, .folder], allowsMultipleSelection: false) { result in
                    if case .success(let urls) = result, let url = urls.first { store.importItem(url) }
                }
            }.tabItem { Label("Files", systemImage: "folder") }.tag(1)
            NavigationStack {
                List(store.games, id: \.path) { folder in
                    VStack(alignment: .leading, spacing: 10) {
                        NavigationLink {
                            GameDetailView(folder: folder)
                        } label: {
                            Label {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(folder.lastPathComponent).font(.headline)
                                    Text("View executables · Export to Madeira / Playport")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            } icon: { Image(systemName: "gamecontroller.fill").foregroundStyle(.tint) }
                        }
                        HStack(spacing: 12) {
                            ShareLink(item: folder) {
                                Label("Share folder", systemImage: "square.and.arrow.up")
                            }
                            .buttonStyle(.bordered)
                            Button(role: .destructive) {
                                pendingGameFolderDeletion = folder
                            } label: {
                                Label("Delete folder", systemImage: "trash")
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .confirmationDialog("Delete extracted game folder?", isPresented: Binding(
                    get: { pendingGameFolderDeletion != nil },
                    set: { if !$0 { pendingGameFolderDeletion = nil } }
                )) {
                    Button("Delete extracted folder permanently", role: .destructive) {
                        if let folder = pendingGameFolderDeletion {
                            guard folder.deletingLastPathComponent().standardizedFileURL == store.library.standardizedFileURL else {
                                store.status = "Cannot delete a folder outside My Games"
                                pendingGameFolderDeletion = nil
                                return
                            }
                            do {
                                try FileManager.default.removeItem(at: folder)
                                store.status = "Extracted game folder deleted"
                                store.refresh()
                            } catch {
                                store.status = "Delete failed: " + error.localizedDescription
                            }
                        }
                        pendingGameFolderDeletion = nil
                    }
                } message: {
                    Text("This deletes the extracted game folder and all files inside it. The original downloaded archive, if present, is not deleted.")
                }
                .safeAreaInset(edge: .bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Storage location (LiveContainer sandbox)")
                            .font(.caption).foregroundStyle(.secondary)
                        Text(store.storagePath).font(.caption2).textSelection(.enabled)
                    }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
                }
                .navigationTitle("My Games")
                .refreshable { store.refresh() }
            }.tabItem { Label("Games", systemImage: "gamecontroller") }.tag(2)
        }
        .alert("Delete downloaded archive?", isPresented: Binding(
            get: { store.extractedArchiveAwaitingDecision != nil },
            set: { if !$0 { store.keepExtractedArchive() } }
        )) {
            Button("Keep archive", role: .cancel) { store.keepExtractedArchive() }
            Button("Delete archive", role: .destructive) { store.deleteExtractedArchive() }
        } message: {
            Text("The game was extracted successfully. Delete the original downloaded archive to free up storage? The prepared game will remain in My Games.")
        }
    }
}

private extension FileManager {
    var defaultGameBridgeDocuments: URL {
        // Always resolve the app's current sandbox at runtime. LiveContainer can
        // remap container locations; never hardcode a /var/mobile/... path.
        urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
}

struct GameDetailView: View {
    let folder: URL
    @State private var report: GameInspection?
    @State private var launchAdvice: MadeiraLaunchAdvisor?
    @State private var launchPlan: GameLaunchPlan?
    @State private var steamResearch: SteamGameResearch.Result?
    @State private var doubleCheck: MadeiraDoubleCheck.Assessment?
    @State private var steamError: String?
    @State private var steamTitle = ""
    @State private var showRunLogPicker = false
    @State private var benchmarkScene = "Repeatable gameplay scene"
    @State private var benchmarkAverage = ""
    @State private var benchmarkLow = ""
    @State private var benchmarkCrashed = false
    @State private var benchmarkMessage: String?
    @State private var benchmarkRevision = 0
    private var benchmarkGameKey: String { folder.standardizedFileURL.path }
    private var benchmarkRanking: [MadeiraBenchmark.Ranked] {
        _ = benchmarkRevision
        return MadeiraBenchmark.ranking(game: benchmarkGameKey, scene: benchmarkScene)
    }
    private func recordBenchmark() {
        guard let match = madeiraMatch,
              let average = Double(benchmarkAverage),
              let low = Double(benchmarkLow) else {
            benchmarkMessage = "Select the Madeira library and enter average FPS and 1% low FPS."
            return
        }
        let profile = match.values.reduce(into: [String: String]()) { result, pair in
            if MadeiraBenchmark.allowed.contains(pair.key) {
                result[pair.key] = (pair.key == "performance" || pair.key == "reducedX87") ? ((pair.value as? Bool == true) ? "true" : "false") : String(describing: pair.value)
            }
        }
        do {
            try MadeiraBenchmark.store(.init(game: benchmarkGameKey, scene: benchmarkScene,
                                           profile: profile, averageFPS: average, lowFPS: low,
                                           crashed: benchmarkCrashed))
            benchmarkRevision += 1
            benchmarkMessage = "Run recorded. Repeat the same scene at least twice per profile."
        } catch { benchmarkMessage = error.localizedDescription }
    }
    private func loadBestProfile() {
        guard let best = benchmarkRanking.first, let match = madeiraMatch else { return }
        prepareFields(match, plan: launchPlan)
        for (key, value) in best.profile where MadeiraBenchmark.allowed.contains(key) {
            proposed[key] = value
            if String(describing: match.values[key] ?? "") != value { selectedFields.insert(key) }
        }
        benchmarkMessage = "Best measured profile loaded for review. Confirm Apply to Madeira to write a backed-up change."
    }
    @State private var runDiagnostics: MadeiraRunDiagnostics.Result?
    @State private var runDiagnosticError: String?
    @AppStorage("anker.automaticLaunchConfig") private var automaticConfig = true
    @State private var configStatus: String?
    @State private var showMadeiraPicker = false
    @State private var madeiraLibraryURL: URL?
    @State private var madeiraOriginalData: Data?
    @State private var madeiraMatch: MadeiraLibraryEditor.Match?
    @State private var madeiraError: String?
    @State private var showMadeiraConfirmation = false
    @State private var proposed: [String: String] = [:]
    @State private var selectedFields: Set<String> = []
    private let configFields = ["arguments", "bits", "graphicsAPI", "resolution", "fpsMode", "performance", "reducedX87"]
    private func proposedChanges() -> [String: Any] {
        guard let match = madeiraMatch else { return [:] }
        var changes: [String: Any] = [:]
        for key in selectedFields {
            guard let value = proposed[key] else { continue }
            let typed: Any
            switch key {
            case "bits", "fpsMode":
                guard let number = Int(value) else { continue }
                typed = number
            case "performance", "reducedX87":
                guard value == "true" || value == "false" else { continue }
                typed = value == "true"
            default: typed = value
            }
            if String(describing: match.values[key] ?? "") != String(describing: typed) { changes[key] = typed }
        }
        return changes
    }
    private func prepareFields(_ match: MadeiraLibraryEditor.Match, plan: GameLaunchPlan?) {
        selectedFields = []
        proposed = [:]
        for key in configFields { proposed[key] = match.values[key].map { String(describing: $0) } ?? "" }
        if automaticConfig, let assessment = doubleCheck {
            for (key, value) in assessment.suggested {
                proposed[key] = value
                if String(describing: match.values[key] ?? "") != value { selectedFields.insert(key) }
            }
        }
    }
    private func researchSteam() async {
        let title = steamTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        steamResearch = nil
        steamError = nil
        do {
            let architecture = report?.candidates.first?.architecture ?? "Unknown"
            let result = try await SteamGameResearch.lookup(title: title, architecture: architecture)
            steamResearch = result
            if let report, let launchPlan {
                doubleCheck = MadeiraDoubleCheck.assess(steam: result, report: report, plan: launchPlan)
                if let match = madeiraMatch, automaticConfig { prepareFields(match, plan: launchPlan) }
            }
        } catch {
            steamError = error.localizedDescription
        }
    }
    var body: some View {
        List {
            if let report {
                Section("Analysis (not a compatibility guarantee)") {
                    Text(report.summary)
                    Text("\(report.fileCount) scanned entries")
                }
                if let launchAdvice {
                    Section("Madeira Launch Advisor · file-based suggestions") {
                        ForEach(launchAdvice.items) { advice in
                            VStack(alignment: .leading, spacing: 5) {
                                HStack {
                                    Text(advice.title).font(.headline)
                                    Spacer()
                                    Text(advice.confidence + " confidence")
                                        .font(.caption2).foregroundStyle(.secondary)
                                }
                                Text(advice.detail)
                                    .font(.subheadline)
                                    .textSelection(.enabled)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
                Section("Steam research · Windows requirements") {
                    TextField("Game title for Steam", text: $steamTitle)
                    Button("Search Steam and analyze requirements") {
                        Task { await researchSteam() }
                    }
                    if let doubleCheck {
                        Text("Double-check results").font(.headline)
                        Text(doubleCheck.confidence).font(.caption).foregroundStyle(.secondary)
                        ForEach(doubleCheck.checks, id: \.self) { check in
                            Text("• " + check).font(.footnote)
                        }
                    }
                    if let steamResearch {
                        Text(steamResearch.title).font(.headline)
                        Text(steamResearch.confidence).font(.caption).foregroundStyle(.secondary)
                        Text(steamResearch.requirements).font(.footnote).textSelection(.enabled)
                        ForEach(steamResearch.suggestions, id: \.self) { note in
                            Text("• " + note).font(.footnote)
                        }
                        if let url = steamResearch.url {
                            Link("View Steam listing", destination: url)
                        }
                    }
                    if let steamError { Text(steamError).font(.caption).foregroundStyle(.secondary) }
                }
                Section("Phase 2 · Madeira run diagnostics") {
                    Text("After testing the game in Madeira, select its run log. Anker checks crashes, graphics initialization, memory and shader compilation. No settings are changed automatically.")
                        .font(.footnote).foregroundStyle(.secondary)
                    Button("Analyze Madeira run log") { showRunLogPicker = true }
                    if let runDiagnostics {
                        Text(runDiagnostics.evidence).font(.caption).foregroundStyle(.secondary)
                        ForEach(runDiagnostics.observations, id: \.self) { Text("Observed: " + $0).font(.footnote) }
                        ForEach(runDiagnostics.suggestions, id: \.self) { Text("Next test: " + $0).font(.footnote) }
                    }
                    if let runDiagnosticError { Text(runDiagnosticError).font(.caption).foregroundStyle(.red) }
                }
                Section("Phase 2 · measured profile comparison") {
                    Text("Measure FPS in the same scene for every run. Anker cannot measure Madeira FPS directly; enter observed average and 1% low.")
                        .font(.footnote).foregroundStyle(.secondary)
                    TextField("Scene identifier", text: $benchmarkScene)
                    TextField("Average FPS", text: $benchmarkAverage)
                        .keyboardType(.decimalPad)
                    TextField("1% low FPS", text: $benchmarkLow)
                        .keyboardType(.decimalPad)
                    Toggle("This run crashed", isOn: $benchmarkCrashed)
                    Button("Save measured run") { recordBenchmark() }
                    if let benchmarkMessage { Text(benchmarkMessage).font(.caption).foregroundStyle(.secondary) }
                    if benchmarkRanking.isEmpty {
                        Text("At least two successful comparable runs per profile are required before ranking.")
                            .font(.caption).foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(benchmarkRanking.enumerated()), id: \.offset) { index, result in
                            VStack(alignment: .leading) {
                                Text(index == 0 ? "Best measured profile" : "Profile " + String(index + 1)).bold()
                                Text("Runs: " + String(result.runs) + " · Crashes: " + String(result.crashes))
                                Text(String(format: "Average %.1f FPS · 1%% low %.1f FPS", result.averageFPS, result.averageLowFPS))
                                Text(result.profile.keys.sorted().map { $0 + ": " + (result.profile[$0] ?? "") }.joined(separator: ", "))
                                    .textSelection(.enabled)
                            }.font(.caption)
                        }
                        Button("Load best measured profile") { loadBestProfile() }
                            .disabled(madeiraMatch == nil)
                    }
                }
                Section("Automatic Config") {
                    Toggle("Automatic Config", isOn: $automaticConfig)
                    Text("Automatically analyze the game and prepare suggested launch settings. No commands are executed and original files are never modified.")
                        .font(.footnote).foregroundStyle(.secondary)
                    if !automaticConfig {
                        Button("Generate configuration now") {
                            launchPlan = GameLaunchPlan.build(root: folder, report: report)
                            configStatus = "Launch configuration generated for review."
                        }
                    }
                    if let configStatus { Text(configStatus).font(.caption).foregroundStyle(.secondary) }
                }
                if let launchPlan {
                    Section("Launch preparation · preview only") {
                        Text("No original files are changed. Use the suggested values manually in Madeira where supported.")
                            .font(.footnote).foregroundStyle(.secondary)
                        LabeledContent("Executable", value: launchPlan.executable ?? "Not found")
                        LabeledContent("Arguments", value: launchPlan.arguments.isEmpty ? "(none)" : launchPlan.arguments)
                        LabeledContent("Working directory", value: launchPlan.workingDirectory)
                        LabeledContent("Confidence", value: launchPlan.confidence)
                        if !launchPlan.environment.isEmpty {
                            Text("Environment variables").font(.headline)
                            ForEach(launchPlan.environment) { item in
                                VStack(alignment: .leading) {
                                    Text(item.label).font(.subheadline).bold()
                                    Text(item.value).font(.caption).textSelection(.enabled)
                                }
                            }
                        }
                        ForEach(launchPlan.notes, id: \.self) { note in
                            Text("• " + note).font(.footnote).textSelection(.enabled)
                        }
                        ShareLink(item: launchPlan.preview) {
                            Label("Share launch plan (text)", systemImage: "square.and.arrow.up")
                        }
                    }
                }
                if let launchPlan {
                    Section("Apply to Madeira · direct library edit") {
                        Text("Close Madeira before applying. Select its madeira-library.json from LiveContainer. Only explicitly selected fields are written; a backup is created.")
                            .font(.footnote).foregroundStyle(.secondary)
                        Button("Select Madeira library") { showMadeiraPicker = true }
                        if let match = madeiraMatch {
                            Text("Matched: " + match.title).font(.headline)
                            Text("Only checked fields are edited. Logs and controller settings stay unchanged.")
                                .font(.caption).foregroundStyle(.secondary)
                            ForEach(configFields, id: \.self) { key in
                                Toggle(key, isOn: Binding(
                                    get: { selectedFields.contains(key) },
                                    set: { enabled in
                                        if enabled { selectedFields.insert(key) }
                                        else { selectedFields.remove(key) }
                                    }
                                ))
                                if selectedFields.contains(key) {
                                    TextField("New value", text: Binding(
                                        get: { proposed[key] ?? "" },
                                        set: { proposed[key] = $0 }
                                    ))
                                    .textInputAutocapitalization(.never)
                                    Text("Current: " + (match.values[key].map { String(describing: $0) } ?? "(unset)"))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Text("Booleans: true/false. FPS mode: raw Madeira integer. Resolution: WIDTHxHEIGHT.")
                                .font(.caption).foregroundStyle(.secondary)
                            ForEach(proposedChanges().keys.sorted(), id: \.self) { key in
                                Text(key + ": " + (match.values[key].map { String(describing: $0) } ?? "(unset)") + " → " + (proposed[key] ?? ""))
                                    .font(.caption).textSelection(.enabled)
                            }
                            Button("Apply to Madeira") { showMadeiraConfirmation = true }
                                .disabled(proposedChanges().isEmpty)
                        }
                        if let madeiraError { Text(madeiraError).font(.footnote).foregroundStyle(.red) }
                    }
                }
                Section("Windows executables — suggested order") {
                    ForEach(report.candidates) { candidate in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(candidate.name).textSelection(.enabled)
                            Text(candidate.architecture).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                if !report.scripts.isEmpty {
                    Section("BAT / CMD scripts (not executed)") {
                        ForEach(report.scripts, id: \.self) { path in
                            NavigationLink(path) {
                                BatchDetailView(root: folder, relativePath: path)
                            }
                        }
                    }
                }
                if !report.warnings.isEmpty {
                    Section("Warnings") {
                        ForEach(report.warnings, id: \.self) { Text($0) }
                    }
                }
                Section("Transfer") {
                    ShareLink(item: folder) { Label("Export prepared game folder", systemImage: "square.and.arrow.up") }
                    Text("Choose the listed EXE in Playport or Madeira. Anker Game Bridge cannot launch Windows executables itself.")
                        .font(.footnote)
                }
            } else {
                ProgressView("Inspecting game files…")
            }
        }
        .navigationTitle(folder.lastPathComponent)
        .fileImporter(isPresented: $showRunLogPicker, allowedContentTypes: [.plainText, .data], allowsMultipleSelection: false) { result in
            do {
                guard let url = try result.get().first else { return }
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                runDiagnostics = try MadeiraRunDiagnostics.inspect(url)
                runDiagnosticError = nil
            } catch {
                runDiagnostics = nil
                runDiagnosticError = error.localizedDescription
            }
        }
        .fileImporter(isPresented: $showMadeiraPicker, allowedContentTypes: [.json], allowsMultipleSelection: false) { result in
            do {
                let selected = try result.get()
                guard let url = selected.first else { return }
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                let (data, entries) = try MadeiraLibraryEditor.read(url)
                guard let exe = launchPlan?.executable else { throw MadeiraLibraryEditor.EditorError.noMatch }
                let matches = MadeiraLibraryEditor.matches(in: entries, executable: exe)
                guard matches.count == 1, let match = matches.first else {
                    throw matches.isEmpty ? MadeiraLibraryEditor.EditorError.noMatch : MadeiraLibraryEditor.EditorError.ambiguousMatch
                }
                madeiraLibraryURL = url
                madeiraOriginalData = data
                madeiraMatch = match
                prepareFields(match, plan: launchPlan)
                madeiraError = nil
            } catch {
                madeiraMatch = nil
                madeiraError = error.localizedDescription
            }
        }
        .confirmationDialog("Apply changes to Madeira?", isPresented: $showMadeiraConfirmation, titleVisibility: .visible) {
            Button("Back up and apply") {
                guard let url = madeiraLibraryURL, let data = madeiraOriginalData,
                      let match = madeiraMatch else { return }
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                do {
                    let backup = try MadeiraLibraryEditor.apply(url: url, expectedData: data,
                                                               entryID: match.id, changes: proposedChanges())
                    madeiraError = "Saved. Backup: " + backup.lastPathComponent
                    let (updated, entries) = try MadeiraLibraryEditor.read(url)
                    madeiraOriginalData = updated
                    madeiraMatch = entries.first(where: { $0["id"] as? String == match.id }).map {
                        MadeiraLibraryEditor.Match(id: match.id, title: match.title, path: match.path,
                                                   arguments: $0["arguments"] as? String ?? "", values: $0)
                    }
                } catch { madeiraError = error.localizedDescription }
            }
        } message: {
            Text("Madeira must be closed. Only checked settings for the matched game will change. A backup will be created alongside the library.")
        }
        .onChange(of: automaticConfig) { enabled in
            if enabled, let report {
                launchPlan = GameLaunchPlan.build(root: folder, report: report)
                configStatus = "Automatic configuration prepared for review."
            } else if !enabled {
                launchPlan = nil
                configStatus = nil
            }
        }
        .task(id: folder.path) {
            steamTitle = folder.lastPathComponent
            if automaticConfig { await researchSteam() }

            let result = await Task.detached(priority: .userInitiated) {
                GameInspection.inspect(folder)
            }.value
            report = result
            launchAdvice = await Task.detached(priority: .utility) {
                MadeiraLaunchAdvisor.inspect(root: folder, report: result)
            }.value
            if automaticConfig {
                launchPlan = await Task.detached(priority: .utility) {
                    GameLaunchPlan.build(root: folder, report: result)
                }.value
                if let steamResearch, let launchPlan {
                    doubleCheck = MadeiraDoubleCheck.assess(steam: steamResearch, report: result, plan: launchPlan)
                }
            } else {
                launchPlan = nil
            }
        }
    }
}

struct BatchDetailView: View {
    let root: URL
    let relativePath: String
    @State private var report: BatchInspection?
    var body: some View {
        List {
            if let report {
                Section("Safety") {
                    Text("Read-only analysis. No Windows commands are executed and no game files are modified.")
                    if let warning = report.warning { Text(warning).foregroundStyle(.orange) }
                }
                Section("Commands") {
                    ForEach(report.lines) { line in
                        VStack(alignment: .leading, spacing: 5) {
                            Text("Line \(line.id) — \(line.classification)").font(.headline)
                            Text(line.command).font(.system(.caption, design: .monospaced)).textSelection(.enabled)
                            Text(line.explanation).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            } else {
                ProgressView("Reading batch script…")
            }
        }
        .navigationTitle(URL(fileURLWithPath: relativePath).lastPathComponent)
        .task(id: relativePath) {
            report = BatchInspection.inspect(root.appendingPathComponent(relativePath), root: root)
        }
    }
}
