import SwiftUI

@main
struct LumenApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
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
