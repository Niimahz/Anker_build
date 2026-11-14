import Foundation

enum AnkerSupport {
    // Set this to the exact verified Buy Me a Coffee profile URL before enabling donations.
    // Example format: https://www.buymeacoffee.com/your-verified-username
    static let buyMeACoffeeProfileURL = ""

    static var donationURL: URL? {
        guard let url = URL(string: buyMeACoffeeProfileURL),
              url.scheme == "https",
              let host = url.host?.lowercased(),
              ["buymeacoffee.com", "www.buymeacoffee.com"].contains(host),
              url.pathComponents.count > 1 else { return nil }
        return url
    }
}
