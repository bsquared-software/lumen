import SwiftUI

@main
struct LumenApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    /// macOS 26+ lets people remove menu bar items in System Settings › Menu Bar. With this
    /// binding Lumen keeps running (shortcuts and links still work) instead of quitting, and
    /// Settings › General can bring the icon back.
    @AppStorage(MenuBarPreference.key) private var showsMenuBarExtra = true

    var body: some Scene {
        MenuBarExtra(isInserted: $showsMenuBarExtra) {
            MenuContent()
                .environment(appDelegate.controller)
        } label: {
            MenuBarLabel()
                .environment(appDelegate.controller)
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(appDelegate.controller)
        }

        #if DEBUG
        Window("Lumen Preview", id: DebugSnapshot.previewWindowID) {
            MenuContent()
                .environment(appDelegate.controller)
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(DebugSnapshot.isEnabled ? .presented : .suppressed)
        .handlesExternalEvents(matching: [])
        #endif
    }
}
