import SwiftUI
import UIKit

final class BackgroundDownloadAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     handleEventsForBackgroundURLSession identifier: String,
                     completionHandler: @escaping () -> Void) {
        guard identifier.hasPrefix(GameDownloadManager.backgroundIdentifier) else {
            completionHandler()
            return
        }
        GameDownloadManager.backgroundCompletionHandler = completionHandler
        // Reconnect to the system session so pending events can be delivered.
        _ = GameDownloadManager.backgroundManagers[identifier] ?? GameDownloadManager(identifier: identifier)
    }
}

@main
struct AnkerGameBridgeApp: App {
    @UIApplicationDelegateAdaptor(BackgroundDownloadAppDelegate.self) var appDelegate
    var body: some Scene { WindowGroup { MainView() } }
}
