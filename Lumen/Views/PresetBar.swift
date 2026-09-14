import LumenCore
import SwiftUI

struct PresetBar: View {
    @Environment(DisplayController.self) private var controller

    var body: some View {
        // Up to three equal columns, so two presets share the row instead of leaving a gap.
        let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: min(max(controller.presets.count, 1), 3))
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(controller.presets) { preset in
                PresetButton(
                    preset: preset,
                    isActive: controller.activePresetID == preset.id,
                    shortcutProblem: controller.hotkeyProblems[preset.id]
                ) {
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
    let shortcutProblem: String?
    let action: () -> Void

    var body: some View {
        let button = Button(action: action) {
            HStack(spacing: 4) {
                Label(preset.name, systemImage: preset.symbol)
                if shortcutProblem != nil {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .symbolRenderingMode(.multicolor)
                        .accessibilityLabel("Shortcut not working")
                }
            }
            .frame(maxWidth: .infinity)
        }
        .controlSize(.large)
        .help(helpText)

        if isActive {
            button.buttonStyle(.borderedProminent)
        } else {
            button.buttonStyle(.bordered)
        }
    }

    private var helpText: String {
        if let shortcutProblem { return "\(preset.name). \(shortcutProblem)" }
        return preset.hotkey.map { "\(preset.name) (\($0.displayString))" } ?? preset.name
    }
}
