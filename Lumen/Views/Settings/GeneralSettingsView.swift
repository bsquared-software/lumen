import ServiceManagement
import SwiftUI

struct GeneralSettingsView: View {
    @State private var status = SMAppService.mainApp.status
    @State private var problem: String?

    var body: some View {
        Form {
            Section {
                Toggle("Open Lumen at login", isOn: Binding(
                    get: { status == .enabled },
                    set: { setLaunchAtLogin($0) }
                ))
                if status == .requiresApproval {
                    LabeledContent("Lumen needs your approval in Login Items.") {
                        Button("Open Login Items") { SMAppService.openSystemSettingsLoginItems() }
                    }
                }
                if let problem {
                    Text(problem)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section("About") {
                LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–")
                Text("Lumen switches displays and brightness through private macOS interfaces. A macOS update can stop a feature working until Lumen is updated.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            problem = nil
        } catch {
            problem = error.localizedDescription
        }
        status = SMAppService.mainApp.status
    }
}
