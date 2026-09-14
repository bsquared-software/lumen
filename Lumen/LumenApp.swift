import SwiftUI

@main
struct LumenApp: App {
    @State private var controller: DisplayController

    init() {
        let controller = DisplayController()
        _controller = State(initialValue: controller)
        Task { await controller.start() }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContent()
                .environment(controller)
        } label: {
            Image(systemName: controller.menuBarSymbol)
                .accessibilityLabel("Lumen")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView()
                .environment(controller)
        }

        #if DEBUG
        Window("Lumen Preview", id: DebugSnapshot.previewWindowID) {
            MenuContent()
                .environment(controller)
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(DebugSnapshot.isEnabled ? .presented : .suppressed)
        #endif
    }
}
