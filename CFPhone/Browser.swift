import UIKit

/// Which app opens Codeforces pages when you choose "open in my browser".
/// "System default" uses whatever iOS has set as the default browser. The others use that app's own link so it
/// works even if the iOS default browser setting isn't honoured (e.g. for Brave).
enum ExternalBrowser: String, CaseIterable, Identifiable {
    case system, brave, chrome, firefox, edge
    var id: String { rawValue }

    var title: String {
        switch self {
        case .system: return "System default"
        case .brave: return "Brave"
        case .chrome: return "Chrome"
        case .firefox: return "Firefox"
        case .edge: return "Edge"
        }
    }

    func link(for url: URL) -> URL? {
        let full = url.absoluteString
        let safe = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        let encoded = full.addingPercentEncoding(withAllowedCharacters: safe) ?? full
        let bare = full.replacingOccurrences(of: "https://", with: "")
        switch self {
        case .system: return nil
        case .brave: return URL(string: "brave://open-url?url=\(encoded)")
        case .chrome: return URL(string: "googlechromes://\(bare)")
        case .firefox: return URL(string: "firefox://open-url?url=\(encoded)")
        case .edge: return URL(string: "microsoft-edge-https://\(bare)")
        }
    }
}

enum Browser {
    static let defaultsKey = "externalBrowser"

    /// Opens `url` in the browser chosen in Settings. If that browser's own link fails (not installed),
    /// falls back to a normal https link, which iOS sends to your default browser.
    @MainActor
    static func open(_ url: URL) {
        let choice = ExternalBrowser(rawValue: UserDefaults.standard.string(forKey: defaultsKey) ?? "system") ?? .system
        if let deep = choice.link(for: url) {
            UIApplication.shared.open(deep, options: [:]) { ok in
                if !ok { UIApplication.shared.open(url, options: [:], completionHandler: nil) }
            }
        } else {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
    }
}
