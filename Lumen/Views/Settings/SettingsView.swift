import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("Presets", systemImage: "square.stack") {
                PresetsSettingsView()
            }
            Tab("General", systemImage: "gearshape") {
                GeneralSettingsView()
            }
        }
        .frame(width: 680, height: 500)
        #if DEBUG
        .task { await DebugSnapshot.recordVisibleWindows(named: "settings") }
        #endif
    }
}
