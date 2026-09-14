import LumenCore
import SwiftUI

struct PresetBar: View {
    @Environment(DisplayController.self) private var controller

    var body: some View {
        // Up to three equal columns, so two presets share the row instead of leaving a gap.
        let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: min(max(controller.presets.count, 1), 3))
        LazyVGrid(columns: columns, spacing: 8) {
            ForEach(Array(controller.presets.enumerated()), id: \.element.id) { index, preset in
                PresetButton(
                    preset: preset,
                    number: index < 9 ? index + 1 : nil,
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
    /// 1–9: pressing the number while the popover is open applies the preset.
    let number: Int?
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
        .presetNumberKey(number)
        .help(helpText)

        if isActive {
            button.buttonStyle(.borderedProminent)
        } else {
            button.buttonStyle(.bordered)
        }
    }

    private var helpText: String {
        let key = number.map { " Press \($0)." } ?? ""
        if let shortcutProblem { return "\(preset.name). \(shortcutProblem)\(key)" }
        return (preset.hotkey.map { "\(preset.name) (\($0.displayString))." } ?? "\(preset.name).") + key
    }
}

private extension View {
    @ViewBuilder
    func presetNumberKey(_ number: Int?) -> some View {
        if let number {
            keyboardShortcut(KeyEquivalent(Character(String(number))), modifiers: [])
        } else {
            self
        }
    }
}
