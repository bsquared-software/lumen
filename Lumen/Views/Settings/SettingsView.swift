import SwiftUI

struct SettingsView: View {
    @Environment(DisplayController.self) private var controller
    /// Reopens on the pane that was last visible.
    @AppStorage("settingsTab") private var tab = SettingsTab.presets

    var body: some View {
        // Each pane sets its own size; the Settings window resizes to fit the visible one.
        TabView(selection: $tab) {
            Tab("Presets", systemImage: "square.stack", value: SettingsTab.presets) {
                PresetsSettingsView()
                    .frame(width: 700, height: 520)
            }
            Tab("Displays", systemImage: "display.2", value: SettingsTab.displays) {
                DisplaysSettingsView()
                    .frame(width: 520, height: 460)
            }
            Tab("General", systemImage: "gearshape", value: SettingsTab.general) {
                GeneralSettingsView()
                    .frame(width: 520, height: 330)
            }
        }
        // A preset created from the popover opens here to be named.
        .onChange(of: controller.presetToEdit) { _, presetID in
            if presetID != nil { tab = .presets }
        }
        #if DEBUG
        .task { await DebugSnapshot.recordVisibleWindows(named: "settings") }
        #endif
    }
}

enum SettingsTab: String, Hashable {
    case presets, displays, general
}
