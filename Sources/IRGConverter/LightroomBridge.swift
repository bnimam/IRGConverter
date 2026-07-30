import AppKit
import Foundation

/// Finding Lightroom and handing files to it.
///
/// The other half of the round trip: the Lightroom plugin sends a selection here,
/// this sends the results back. Opening a file with Lightroom Classic puts it in
/// front of the Import dialog, which is the same thing dropping it on the icon does.
enum LightroomBridge {
    /// Tried in order. Lightroom Classic first, since it is the version with the
    /// plugin SDK and therefore the one the other half of this round trip runs in.
    ///
    /// Adobe has shipped a new bundle identifier for most major versions, so this is
    /// a list rather than a constant. Anything not installed is skipped.
    static let bundleIdentifiers = [
        "com.adobe.LightroomClassicCC7",   // Lightroom Classic 7 and later
        "com.adobe.LightroomClassic",
        "com.adobe.Lightroom6",            // Lightroom 6, the last perpetual licence
        "com.adobe.Lightroom5",
        "com.adobe.lightroomCC",           // Lightroom (the cloud one)
        "com.adobe.Lightroom",
    ]

    /// Where Lightroom is, or nil.
    ///
    /// Launch Services is asked first, which finds it wherever it is installed and
    /// whatever it is called. The /Applications sweep is a fallback for a copy that
    /// has never been launched, and so may not be registered yet.
    static func locate() -> URL? {
        for identifier in bundleIdentifiers {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) {
                return url
            }
        }

        let applications = URL(fileURLWithPath: "/Applications", isDirectory: true)
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: applications, includingPropertiesForKeys: nil)) ?? []
        // "Adobe Lightroom Classic" is a folder containing the app of the same name,
        // so both the bundle and its enclosing folder have to be considered.
        for entry in contents where entry.lastPathComponent.hasPrefix("Adobe Lightroom") {
            if entry.pathExtension == "app" { return entry }
            let nested = entry.appendingPathComponent(entry.lastPathComponent + ".app")
            if FileManager.default.fileExists(atPath: nested.path) { return nested }
        }
        return nil
    }

    static var isInstalled: Bool { locate() != nil }

    enum BridgeError: LocalizedError {
        case notFound

        var errorDescription: String? {
            switch self {
            case .notFound:
                return "Lightroom was not found on this Mac. The converted files were "
                    + "still written — import them by hand."
            }
        }
    }

    /// Open `urls` in Lightroom. Calls back on the main queue.
    static func open(_ urls: [URL], completion: @escaping (Error?) -> Void) {
        guard !urls.isEmpty else { return completion(nil) }
        guard let app = locate() else { return completion(BridgeError.notFound) }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open(urls, withApplicationAt: app,
                                configuration: configuration) { _, error in
            DispatchQueue.main.async { completion(error) }
        }
    }
}
