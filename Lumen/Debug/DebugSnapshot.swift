#if DEBUG
import AppKit

/// Development aid, compiled out of Release builds.
///
/// When `LUMEN_SNAPSHOT_DIR` is set, Lumen opens a preview window with the popover's content
/// and appends `name windowNumber` lines to `windows.txt` in that directory. Capture a window
/// on its own with `screencapture -o -l <windowNumber> out.png`, which records nothing else on
/// screen. `LUMEN_OPEN_SETTINGS=1` also opens Settings.
@MainActor
enum DebugSnapshot {
    static let previewWindowID = "debug-popover-preview"

    static var directory: URL? {
        ProcessInfo.processInfo.environment["LUMEN_SNAPSHOT_DIR"].map { URL(filePath: $0) }
    }

    static var isEnabled: Bool { directory != nil }

    static var shouldOpenSettings: Bool {
        ProcessInfo.processInfo.environment["LUMEN_OPEN_SETTINGS"] == "1"
    }

    static func recordVisibleWindows(named name: String) async {
        guard let directory else { return }
        try? await Task.sleep(for: .seconds(1))
        let lines = NSApp.windows
            .filter { $0.isVisible && !$0.className.contains("StatusBar") }
            .map { "\(name) \($0.windowNumber)\n" }
            .joined()
        let file = directory.appending(path: "windows.txt")
        let existing = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        try? (existing + lines).write(to: file, atomically: true, encoding: .utf8)
    }
}
#endif
