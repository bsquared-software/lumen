import SwiftUI

/// The menu bar icon. It is the one view that is always on screen, so it also opens Settings
/// when something outside SwiftUI asks for it (Lumen being launched again, the popover's
/// "Save as Preset").
struct MenuBarLabel: View {
    @Environment(DisplayController.self) private var controller
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Image(systemName: controller.menuBarSymbol)
            // A preset changes the icon rarely, so a replace transition marks it without noise.
            .contentTransition(.symbolEffect(.replace))
            .accessibilityLabel("Lumen")
            .onChange(of: controller.settingsRequest) {
                NSApplication.shared.activate()
                openSettings()
            }
    }
}
