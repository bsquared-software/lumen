import SwiftUI

/// The popover under the menu bar icon.
struct MenuContent: View {
    @Environment(DisplayController.self) private var controller
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("Presets")
                    .font(.headline)
                Spacer()
                if controller.isBusy {
                    if let activity = controller.activity {
                        Text(activity)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if controller.isOfferingLoginItem {
                LoginItemOffer()
            }

            PresetBar()

            ForEach(controller.visibleDisplays) { detail in
                DisplayCard(detail: detail)
            }

            if !controller.notices.isEmpty {
                HStack(alignment: .top, spacing: 6) {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(controller.notices, id: \.self) { notice in
                            Label(notice, systemImage: "exclamationmark.triangle")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    Spacer(minLength: 0)
                    Button("Dismiss", systemImage: "xmark.circle.fill") {
                        controller.dismissNotices()
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("Dismiss these messages")
                }
            }

            Divider()

            HStack {
                Button("Reconnect All", systemImage: "arrow.triangle.2.circlepath") {
                    Task { await controller.reconnectAll() }
                }
                .disabled(!controller.hasDisconnectedDisplays || controller.isBusy)

                Spacer()

                // Opens Settings to name the new preset, hence the ellipsis.
                Button("Save Current Setup as Preset…", systemImage: "plus.rectangle.on.rectangle") {
                    controller.saveCurrentSetupAndEdit()
                }
                .labelStyle(.iconOnly)
                .help("Save how your displays are set up now as a preset")

                Button("Settings…", systemImage: "gearshape") {
                    NSApplication.shared.activate()
                    openSettings()
                }
                .labelStyle(.iconOnly)
                .keyboardShortcut(",", modifiers: .command)
                .help("Open settings (⌘,)")

                Button("Quit Lumen", systemImage: "power") {
                    NSApplication.shared.terminate(nil)
                }
                .labelStyle(.iconOnly)
                .keyboardShortcut("q", modifiers: .command)
                .help(controller.hasDisconnectedDisplays ? "Quit Lumen and switch displays back on (⌘Q)" : "Quit Lumen (⌘Q)")
            }
            .buttonStyle(.borderless)
        }
        .padding(14)
        .frame(width: 340)
        .task {
            await controller.refresh()
            #if DEBUG
            await DebugSnapshot.recordVisibleWindows(named: "popover")
            if DebugSnapshot.shouldOpenSettings {
                NSApplication.shared.activate()
                openSettings()
            }
            #endif
        }
        // Messages describe the last action; don't greet the next visit with stale ones.
        .onDisappear { controller.dismissNotices() }
    }
}

/// Asked once: without opening at login, Lumen isn't running after a restart and its shortcuts
/// do nothing.
private struct LoginItemOffer: View {
    @Environment(DisplayController.self) private var controller

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Open Lumen at login so your shortcuts still work after a restart?", systemImage: "power.circle")
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Not Now") { controller.declineLoginItem() }
                Button("Open at Login") { controller.acceptLoginItem() }
                    .buttonStyle(.borderedProminent)
            }
            .controlSize(.small)
        }
    }
}
