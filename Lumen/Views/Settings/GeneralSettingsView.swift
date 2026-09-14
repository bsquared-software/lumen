import AppKit
import SwiftUI

struct GeneralSettingsView: View {
    @AppStorage(MenuBarPreference.key) private var showsMenuBarExtra = true
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
                .controlSize(.mini)
                if needsApproval {
                    LabeledContent("Lumen needs your approval in Login Items.") {
                        Button("Open Login Items…") { LoginItem.openSystemSettings() }
                    }
                }
                if let problem {
                    Label(problem, systemImage: "xmark.octagon")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                Toggle("Show Lumen in menu bar", isOn: $showsMenuBarExtra)
                    .controlSize(.mini)
            } footer: {
                Text("With the menu bar icon hidden, shortcuts and links keep working. Open Lumen again from Spotlight to get back here.")
            }

            Section("About") {
                LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "–")
                LabeledContent("Credits and version details") {
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
