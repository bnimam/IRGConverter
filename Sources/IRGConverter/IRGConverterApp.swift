import AppKit
import SwiftUI

@main
struct IRGConverterApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowResizability(.contentMinSize)
        .windowStyle(.titleBar)
    }
}

/// Accepts files from outside the app: selecting a batch in the Finder and
/// choosing Open With, dropping a selection onto the Dock icon, or passing paths
/// on the command line.
///
/// Worth having now that the app edits many photos at once — the alternative is
/// re-finding forty files in an open panel. URLs arrive by notification rather
/// than through a binding because `application(_:open:)` can fire before the
/// window's view exists; `ContentView` picks up whatever queued in the meantime
/// when it appears.
final class AppDelegate: NSObject, NSApplicationDelegate {
    static let openFiles = Notification.Name("io.geospace.irgconverter.openFiles")

    /// Files delivered before anything was listening.
    private(set) static var pending: [URL] = []

    func application(_ application: NSApplication, open urls: [URL]) {
        Self.deliver(urls)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Paths on the command line, so `open -a IRGConverter --args a.ORF b.ORF`
        // and `IRGConverter.app/Contents/MacOS/IRGConverter a.ORF` both work.
        let arguments = CommandLine.arguments.dropFirst().filter { !$0.hasPrefix("-") }
        guard !arguments.isEmpty else { return }
        Self.deliver(arguments.map { URL(fileURLWithPath: $0) })
    }

    private static func deliver(_ urls: [URL]) {
        let existing = urls.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !existing.isEmpty else { return }
        pending += existing
        NotificationCenter.default.post(name: openFiles, object: nil,
                                        userInfo: ["urls": existing])
    }

    /// Hand over anything that queued before the view was listening.
    static func takePending() -> [URL] {
        defer { pending = [] }
        return pending
    }
}
