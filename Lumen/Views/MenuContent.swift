import SwiftUI

/// The popover under the menu bar icon.
struct MenuContent: View {
    @Environment(DisplayController.self) private var controller
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Presets")
                    .font(.headline)
                Spacer()
                if controller.isBusy {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            PresetBar()

            ForEach(controller.visibleDisplays) { detail in
                DisplayCard(detail: detail)
            }

            if !controller.notices.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(controller.notices, id: \.self) { notice in
                        Label(notice, systemImage: "exclamationmark.triangle")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Divider()

            HStack {
                Button("Reconnect All", systemImage: "arrow.triangle.2.circlepath") {
                    Task { await controller.reconnectAll() }
                }
                .disabled(!controller.hasDisconnectedDisplays || controller.isBusy)

                Spacer()

                Button("Settings…", systemImage: "gearshape") {
                    NSApplication.shared.activate()
                    openSettings()
                }
                .labelStyle(.iconOnly)
                .help("Settings")

                Button("Quit Lumen", systemImage: "power") {
                    NSApplication.shared.terminate(nil)
                }
                .labelStyle(.iconOnly)
                .help("Quit Lumen")
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
    }
}
