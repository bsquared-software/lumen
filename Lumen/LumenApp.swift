import SwiftUI

@main
struct LumenApp: App {
    var body: some Scene {
        MenuBarExtra("Lumen", systemImage: "sun.max") {
            Button("Quit Lumen") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
}
