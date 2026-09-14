import LumenCore
import SwiftUI

/// One display in the popover: on/off, brightness and resolution.
struct DisplayCard: View {
    @Environment(DisplayController.self) private var controller
    let detail: DisplayDetail

    private var isOn: Bool { detail.known.status == .online }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 10) {
                    Image(systemName: detail.known.info.isBuiltin ? "laptopcomputer" : "display")
                        .font(.title2)
                        .foregroundStyle(isOn ? .primary : .secondary)
                        .frame(width: 30)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(detail.known.info.name)
                            .font(.headline)
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Toggle("Switched on", isOn: Binding(
                        get: { isOn },
                        set: { on in Task { await controller.setConnected(on, detail.id) } }
                    ))
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .disabled(controller.isBusy)
                }

                if isOn {
                    if let brightness = detail.brightness {
                        BrightnessSlider(value: brightness) { controller.setBrightness($0, for: detail.id) }
                    }
                    if let problem = controller.brightnessErrors[detail.id] {
                        Label(problem, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    ModePickers(detail: detail)
                }
            }
            .padding(4)
        }
    }

    private var subtitle: String {
        guard isOn else { return "Switched off" }
        guard let mode = detail.currentMode else { return "On" }
        return "\(mode.width) × \(mode.height)\(mode.isHiDPI ? " HiDPI" : "") · \(ModeCatalogue.refreshLabel(mode.refreshRate))"
    }
}

private struct BrightnessSlider: View {
    let value: Double
    let onChange: (Double) -> Void

    /// Holds the thumb still while dragging, even if a background refresh reports an older value.
    @State private var draft: Double?

    var body: some View {
        let shown = draft ?? value
        HStack(spacing: 8) {
            Image(systemName: "sun.min")
                .foregroundStyle(.secondary)
            Slider(
                value: Binding(get: { shown }, set: { draft = $0; onChange($0) }),
                in: 0...1
            ) {
                Text("Brightness")
            } onEditingChanged: { editing in
                if !editing { draft = nil }
            }
            .labelsHidden()
            Image(systemName: "sun.max")
                .foregroundStyle(.secondary)
            Text(shown, format: .percent.precision(.fractionLength(0)))
                .font(.caption)
                .monospacedDigit()
                .frame(width: 36, alignment: .trailing)
        }
    }
}

private struct ModePickers: View {
    @Environment(DisplayController.self) private var controller
    let detail: DisplayDetail

    var body: some View {
        let options = detail.options
        let current = detail.currentMode.flatMap { ModeCatalogue.option(containing: $0, in: options) }

        HStack(spacing: 8) {
            Picker("Resolution", selection: Binding(
                get: { current?.id ?? "" },
                set: { id in
                    guard let option = options.first(where: { $0.id == id }) else { return }
                    Task { await controller.select(option, refreshRate: nil, for: detail.id) }
                }
            )) {
                if current == nil { Text("Resolution").tag("") }
                Section("HiDPI") {
                    ForEach(options.filter(\.isHiDPI)) { Text("\($0.label) HiDPI").tag($0.id) }
                }
                Section("Standard") {
                    ForEach(options.filter { !$0.isHiDPI }) { Text($0.label).tag($0.id) }
                }
            }

            if let current {
                // Tagged by rounded key: CoreGraphics reports the same rate with float noise.
                Picker("Refresh rate", selection: Binding(
                    get: { detail.currentMode.map { DisplayMode.refreshKey($0.refreshRate) } ?? 0 },
                    set: { key in
                        guard let rate = current.refreshRates.first(where: { DisplayMode.refreshKey($0) == key }) else { return }
                        Task { await controller.select(current, refreshRate: rate, for: detail.id) }
                    }
                )) {
                    ForEach(current.refreshRates, id: \.self) { Text(ModeCatalogue.refreshLabel($0)).tag(DisplayMode.refreshKey($0)) }
                }
                .frame(width: 92)
            }
        }
        .labelsHidden()
        .pickerStyle(.menu)
        .disabled(controller.isBusy)
    }
}
