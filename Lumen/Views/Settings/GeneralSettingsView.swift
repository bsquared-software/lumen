import AppKit
import SwiftUI

struct GeneralSettingsView: View {
    @State private var isEnabled = LoginItem.isEnabled
    @State private var needsApproval = LoginItem.needsApproval
    @State private var problem: String?

    var body: some View {
        Form {
            Section {
                Toggle("Open Lumen at login", isOn: Binding(
                    get: { isEnabled },
                    set: { setLaunchAtLogin($0) }
                ))
                if needsApproval {
                    LabeledContent("Lumen needs your approval in Login Items.") {
                        Button("Open Login Items") { LoginItem.openSystemSettings() }
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
                LabeledContent("Lumen has no app menu, so its About window lives here.") {
                    Button("About Lumen") {
                        NSApplication.shared.activate()
                        NSApplication.shared.orderFrontStandardAboutPanel(nil)
                    }
                }
                Text("Lumen switches displays and brightness through private macOS interfaces. A macOS update can stop a feature working until Lumen is updated.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        // Approval happens in System Settings, so re-read the status whenever this tab appears.
        .onAppear(perform: readStatus)
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try LoginItem.setEnabled(enabled)
            problem = nil
        } catch {
            problem = error.localizedDescription
        }
        readStatus()
    }

    private func readStatus() {
        isEnabled = LoginItem.isEnabled
        needsApproval = LoginItem.needsApproval
    }
}
