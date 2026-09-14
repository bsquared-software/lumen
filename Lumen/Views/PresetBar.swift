import LumenCore
import SwiftUI

struct PresetBar: View {
    @Environment(DisplayController.self) private var controller

    var body: some View {
        // Up to three equal columns, so two presets share the row instead of leaving a gap.
        let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: min(max(controller.presets.count, 1), 3))
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(controller.presets) { preset in
                PresetButton(preset: preset, isActive: controller.activePresetID == preset.id) {
                    Task { await controller.apply(preset) }
                }
            }
        }
        .disabled(controller.isBusy)
    }
}

private struct PresetButton: View {
    let preset: Preset
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        let button = Button(action: action) {
            Label(preset.name, systemImage: preset.symbol)
                .frame(maxWidth: .infinity)
        }
        .controlSize(.large)
        .help(preset.hotkey.map { "\(preset.name) (\($0.displayString))" } ?? preset.name)

        if isActive {
            button.buttonStyle(.borderedProminent)
        } else {
            button.buttonStyle(.bordered)
        }
    }
}
