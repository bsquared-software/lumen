import AppKit
import LumenCore

/// Owns the controller and handles what only an app delegate can: `lumen://` links and being
/// launched again while already running.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let controller = DisplayController()

    func applicationDidFinishLaunching(_ notification: Notification) {
        Task { await controller.start() }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            Task { await controller.open(url) }
        }
    }

    /// A menu bar app shows no window when launched again from Spotlight or Finder, which feels
    /// broken. Open Settings instead.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        controller.requestSettings()
        return false
    }
}
