import AppKit
import LumenCore
import SwiftUI

struct PresetsSettingsView: View {
    @Environment(DisplayController.self) private var controller
    @State private var selection: Preset.ID?
    @State private var pendingDeletion: Preset?

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                List(selection: $selection) {
                    ForEach(controller.presets) { preset in
                        Label(preset.name, systemImage: preset.symbol)
                            .tag(preset.id)
                    }
                    .onMove { source, destination in
                        var reordered = controller.presets
                        reordered.move(fromOffsets: source, toOffset: destination)
                        controller.reorderPresets(reordered)
                    }
                }
                .listStyle(.inset)

                Divider()

                HStack(spacing: 4) {
                    Button("Add Preset from Current Setup", systemImage: "plus") {
                        selection = controller.saveCurrentAsPreset().id
                    }
                    .help("Add Preset from Current Setup")
                    Button("Delete Preset", systemImage: "minus") {
                        pendingDeletion = controller.presets.first { $0.id == selection }
                    }
                    .disabled(selection == nil)
                    .help("Delete Preset")
                    Spacer()
                }
                .buttonStyle(.borderless)
                .labelStyle(.iconOnly)
                .padding(8)
            }
            .frame(width: 200)

            Divider()

            if let selection, let preset = controller.presets.first(where: { $0.id == selection }) {
                PresetEditor(preset: preset, startRenaming: controller.presetToEdit == selection)
                    .id(selection)
            } else {
                ContentUnavailableView(
                    "No Preset Selected", systemImage: "square.stack",
                    description: Text("Pick a preset, or add one from how your displays are set up right now.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .onAppear { selection = controller.presetToEdit ?? selection ?? controller.presets.first?.id }
        .onChange(of: controller.presetToEdit) { _, presetID in
            if let presetID { selection = presetID }
        }
        .confirmationDialog(
            "Delete “\(pendingDeletion?.name ?? "")”?",
            isPresented: Binding(get: { pendingDeletion != nil }, set: { if !$0 { pendingDeletion = nil } }),
            presenting: pendingDeletion
        ) { preset in
            Button("Delete", role: .destructive) {
                controller.delete(preset.id)
                selection = controller.presets.first?.id
            }
        } message: { preset in
            if let hotkey = preset.hotkey {
                Text("Its shortcut \(hotkey.displayString) will stop working. This can’t be undone.")
            } else {
                Text("This can’t be undone.")
            }
        }
    }
}

private struct PresetEditor: View {
    @Environment(DisplayController.self) private var controller
    @State private var draft: Preset
    @FocusState private var isNameFocused: Bool
    private let startRenaming: Bool

    init(preset: Preset, startRenaming: Bool) {
        _draft = State(initialValue: preset)
        self.startRenaming = startRenaming
    }

    static let symbols: [(symbol: String, name: String)] = [
        ("moon.stars", "Night"), ("sun.max", "Day"), ("display.2", "Displays"), ("laptopcomputer", "Laptop"),
        ("gamecontroller", "Gaming"), ("film", "Film"), ("briefcase", "Work"), ("sparkles", "Focus"),
    ]

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $draft.name)
                    .focused($isNameFocused)
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
                LabeledContent("Link") {
                    HStack {
                        Text(controller.link(for: draft).absoluteString)
                            .textSelection(.enabled)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Button("Copy Link", systemImage: "doc.on.doc") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(controller.link(for: draft).absoluteString, forType: .string)
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .help("Copy Link. Open it from Shortcuts, Raycast or Terminal to apply this preset.")
                    }
                }
            }

            ForEach($draft.displays) { $target in
                let detail = controller.displays.first { $0.id == target.uuid }
                Section(detail?.known.displayName ?? target.name) {
                    TargetEditor(target: $target, detail: detail)
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
        .onAppear {
            guard startRenaming else { return }
            isNameFocused = true
            controller.didStartEditing(draft.id)
        }
    }
}

private struct TargetEditor: View {
    @Binding var target: DisplayTarget
    let detail: DisplayDetail?

    private var options: [ResolutionOption] {
        ModeCatalogue.essentialOptions(from: detail?.options ?? [], keeping: target.mode)
    }

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
                        Text(ModeCatalogue.summary(mode))
                        Button("Don’t Change") { target.mode = nil }
                    }
                } else {
                    Text("Don’t Change").foregroundStyle(.secondary)
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
                Text("Don’t Change").tag("")
                Section("HiDPI") {
                    ForEach(options.filter(\.isHiDPI)) { Text("\($0.label) HiDPI").tag($0.id) }
                }
                Section("Standard") {
                    ForEach(options.filter { !$0.isHiDPI }) { Text($0.label).tag($0.id) }
                }
            }

            if let selected, let mode = target.mode {
                Picker("Refresh rate", selection: Binding(
                    get: { DisplayMode.refreshKey(mode.refreshRate) },
                    set: { key in
                        guard let rate = selected.refreshRates.first(where: { DisplayMode.refreshKey($0) == key }) else { return }
                        target.mode = ModeCatalogue.mode(for: selected, refreshRate: rate, in: detail?.modes ?? [])
                    }
                )) {
                    ForEach(selected.refreshRates, id: \.self) { Text(ModeCatalogue.refreshLabel($0)).tag(DisplayMode.refreshKey($0)) }
                }
            }
        }
    }
}
