import SwiftUI

struct SettingsView: View {
    @Environment(DisplayController.self) private var controller
    @State private var tab = SettingsTab.presets

    var body: some View {
        TabView(selection: $tab) {
            Tab("Presets", systemImage: "square.stack", value: SettingsTab.presets) {
                PresetsSettingsView()
            }
            Tab("Displays", systemImage: "display.2", value: SettingsTab.displays) {
                DisplaysSettingsView()
            }
            Tab("General", systemImage: "gearshape", value: SettingsTab.general) {
                GeneralSettingsView()
            }
        }
        .frame(width: 680, height: 500)
        // A preset created from the popover opens here to be named.
        .onChange(of: controller.presetToEdit) { _, presetID in
            if presetID != nil { tab = .presets }
        }
        #if DEBUG
        .task { await DebugSnapshot.recordVisibleWindows(named: "settings") }
        #endif
    }
}

enum SettingsTab: Hashable {
    case presets, displays, general
}
