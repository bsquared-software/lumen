import LumenCore
import SwiftUI

struct PresetsSettingsView: View {
    @Environment(DisplayController.self) private var controller
    @State private var selection: Preset.ID?

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                List(controller.presets, selection: $selection) { preset in
                    Label(preset.name, systemImage: preset.symbol)
                        .tag(preset.id)
                }
                .listStyle(.inset)

                Divider()

                HStack(spacing: 4) {
                    Button("Add Preset from Current Setup", systemImage: "plus") {
                        selection = controller.saveCurrentAsPreset(named: "New Preset").id
                    }
                    Button("Delete Preset", systemImage: "minus") {
                        guard let selection else { return }
                        controller.delete(selection)
                        self.selection = controller.presets.first?.id
                    }
                    .disabled(selection == nil)
                    Spacer()
                }
                .buttonStyle(.borderless)
                .labelStyle(.iconOnly)
                .padding(8)
            }
            .frame(width: 200)

            Divider()

            if let selection, let preset = controller.presets.first(where: { $0.id == selection }) {
                PresetEditor(preset: preset)
                    .id(selection)
            } else {
                ContentUnavailableView(
                    "No Preset Selected", systemImage: "square.stack",
                    description: Text("Pick a preset, or add one from how your displays are set up right now.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear { selection = selection ?? controller.presets.first?.id }
    }
}

private struct PresetEditor: View {
    @Environment(DisplayController.self) private var controller
    @State private var draft: Preset

    init(preset: Preset) {
        _draft = State(initialValue: preset)
    }

    static let symbols: [(symbol: String, name: String)] = [
        ("moon.stars", "Night"), ("sun.max", "Day"), ("display.2", "Displays"), ("laptopcomputer", "Laptop"),
        ("gamecontroller", "Gaming"), ("film", "Film"), ("briefcase", "Work"), ("sparkles", "Focus"),
    ]

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $draft.name)
                Picker("Icon", selection: $draft.symbol) {
                    ForEach(Self.symbols, id: \.symbol) { Label($0.name, systemImage: $0.symbol).tag($0.symbol) }
                }
                LabeledContent("Shortcut") {
                    VStack(alignment: .trailing, spacing: 4) {
                        ShortcutRecorder(hotkey: $draft.hotkey) { recording in
                            recording ? controller.suspendHotkeys() : controller.resumeHotkeys()
                        }
                        if let problem = controller.hotkeyProblems[draft.id] {
                            Text(problem)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                }
            }

            ForEach($draft.displays) { $target in
                Section(target.name) {
                    TargetEditor(target: $target, detail: controller.displays.first { $0.id == target.uuid })
                }
            }

            Section {
                HStack {
                    Button("Apply Now") {
                        Task { await controller.apply(draft) }
                    }
                    .disabled(controller.isBusy)
                    Button("Update from Current Setup") {
                        controller.updateFromCurrentSetup(draft.id)
                        if let saved = controller.presets.first(where: { $0.id == draft.id }) { draft = saved }
                    }
                    .help("Replace this preset’s display settings with how your displays are set up right now.")
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: draft) { _, updated in controller.update(updated) }
    }
}

private struct TargetEditor: View {
    @Binding var target: DisplayTarget
    let detail: DisplayDetail?

    private var options: [ResolutionOption] { ModeCatalogue.options(from: detail?.modes ?? []) }

    var body: some View {
        Toggle("Switched on", isOn: $target.connected)

        if target.connected {
            Toggle("Set brightness", isOn: Binding(
                get: { target.brightness != nil },
                set: { target.brightness = $0 ? detail?.brightness ?? 0.5 : nil }
            ))
            if let brightness = target.brightness {
                LabeledContent("Brightness") {
                    HStack {
                        Slider(value: Binding(get: { brightness }, set: { target.brightness = $0 }), in: 0...1)
                        Text(brightness, format: .percent.precision(.fractionLength(0)))
                            .monospacedDigit()
                            .frame(width: 40, alignment: .trailing)
                    }
                    .frame(width: 240)
                }
            }
            resolution
        }

        if detail == nil || detail?.known.status == .unavailable {
            Text("Not plugged in right now.")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var resolution: some View {
        let selected = target.mode.flatMap { ModeCatalogue.option(containing: $0, in: options) }

        if options.isEmpty {
            LabeledContent("Resolution") {
                if let mode = target.mode {
                    HStack {
                        Text(Self.summary(mode))
                        Button("Leave As It Is") { target.mode = nil }
                    }
                } else {
                    Text("Leave as it is").foregroundStyle(.secondary)
                }
            }
        } else {
            Picker("Resolution", selection: Binding(
                get: { selected?.id ?? "" },
                set: { id in
                    guard let option = options.first(where: { $0.id == id }),
                          let rate = ModeCatalogue.preferredRefreshRate(for: option, current: target.mode?.refreshRate)
                    else { target.mode = nil; return }
                    target.mode = ModeCatalogue.mode(for: option, refreshRate: rate, in: detail?.modes ?? [])
                }
            )) {
                Text("Leave as it is").tag("")
                Section("HiDPI") {
                    ForEach(options.filter(\.isHiDPI)) { Text("\($0.label) HiDPI").tag($0.id) }
                }
                Section("Standard") {
                    ForEach(options.filter { !$0.isHiDPI }) { Text($0.label).tag($0.id) }
                }
            }

            if let selected, let mode = target.mode {
                Picker("Refresh rate", selection: Binding(
                    get: { mode.refreshRate },
                    set: { rate in target.mode = ModeCatalogue.mode(for: selected, refreshRate: rate, in: detail?.modes ?? []) }
                )) {
                    ForEach(selected.refreshRates, id: \.self) { Text(ModeCatalogue.refreshLabel($0)).tag($0) }
                }
            }
        }
    }

    static func summary(_ mode: DisplayMode) -> String {
        "\(mode.width) × \(mode.height)\(mode.isHiDPI ? " HiDPI" : "") · \(ModeCatalogue.refreshLabel(mode.refreshRate))"
    }
}
