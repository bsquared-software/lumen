import LumenCore
import SwiftUI

struct PresetsSettingsView: View {
    @Environment(DisplayController.self) private var controller
    @State private var selection: Preset.ID?
    @State private var pendingDeletion: Preset?

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(controller.presets) { preset in
                    PresetRow(preset: preset)
                        .tag(preset.id)
                        // Actions, so no icons (macOS 27 hides them anyway), and unavailable
                        // items are hidden rather than dimmed.
                        .contextMenu {
                            if !controller.isBusy {
                                Button("Apply") {
                                    Task { await controller.apply(preset) }
                                }
                            }
                            Button("Duplicate") {
                                selection = controller.duplicate(preset.id)?.id
                            }
                            Button("Copy Link") {
                                controller.copyLink(for: preset)
                            }
                            Divider()
                            Button("Delete…", role: .destructive) {
                                pendingDeletion = preset
                            }
                        }
                }
                .onMove { source, destination in
                    var reordered = controller.presets
                    reordered.move(fromOffsets: source, toOffset: destination)
                    controller.reorderPresets(reordered)
                }
            }
            .frame(minWidth: 220)
            .navigationSplitViewColumnWidth(min: 220, ideal: 230)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                HStack(spacing: 4) {
                    Button("Add Preset from Current Setup", systemImage: "plus") {
                        selection = controller.saveCurrentAsPreset().id
                    }
                    .help("Add a preset from your current setup")
                    Button("Delete Preset…", systemImage: "minus") {
                        pendingDeletion = controller.presets.first { $0.id == selection }
                    }
                    .disabled(selection == nil)
                    .help("Delete the selected preset")
                    Spacer()
                }
                .buttonStyle(.borderless)
                .labelStyle(.iconOnly)
                .padding(8)
            }
            .toolbar(removing: .sidebarToggle)
        } detail: {
            if let selection, let preset = controller.presets.first(where: { $0.id == selection }) {
                PresetEditor(preset: preset, startRenaming: controller.presetToEdit == selection)
                    .id(selection)
            } else {
                ContentUnavailableView {
                    Label("No Preset Selected", systemImage: "square.stack")
                } description: {
                    Text("Pick a preset, or save how your displays are set up right now.")
                } actions: {
                    Button("Add Preset from Current Setup") {
                        selection = controller.saveCurrentAsPreset().id
                    }
                }
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
            // Apple's alert guidance: an action the person deliberately chose (they picked
            // Delete…) isn't given the destructive style.
            Button("Delete") {
                controller.delete(preset.id)
                if selection == preset.id { selection = controller.presets.first?.id }
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

private struct PresetRow: View {
    let preset: Preset

    var body: some View {
        HStack {
            Label(preset.name, systemImage: preset.symbol)
                .lineLimit(1)
                .layoutPriority(1)
            Spacer()
            if let hotkey = preset.hotkey {
                Text(hotkey.displayString)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct PresetEditor: View {
    @Environment(DisplayController.self) private var controller
    @State private var draft: Preset
    /// After Apply Now, show what happened here, not only in the popover.
    @State private var appliedFromHere = false
    @FocusState private var isNameFocused: Bool
    private let startRenaming: Bool

    init(preset: Preset, startRenaming: Bool) {
        _draft = State(initialValue: preset)
        self.startRenaming = startRenaming
    }

    static let symbols: [(symbol: String, name: String)] = [
        ("moon.stars", "Night"), ("sun.max", "Day"), ("sunrise", "Morning"), ("sunset", "Evening"),
        ("bed.double", "Sleep"), ("display.2", "Displays"), ("laptopcomputer", "Laptop"), ("tv", "TV"),
        ("gamecontroller", "Gaming"), ("film", "Film"), ("headphones", "Music"), ("book", "Reading"),
        ("briefcase", "Work"), ("person.2", "Meeting"), ("cup.and.saucer", "Break"), ("sparkles", "Focus"),
    ]

    var body: some View {
        let known = controller.displays.map(\.known)

        Form {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    TextField("Name", text: $draft.name)
                        .focused($isNameFocused)
                    if let problem = PresetFactory.nameProblem(draft.name, for: draft.id, in: controller.presets) {
                        Label(problem, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                Picker("Icon", selection: $draft.symbol) {
                    ForEach(Self.symbols, id: \.symbol) {
                        Label($0.name, systemImage: $0.symbol)
                            .labelStyle(.titleAndIcon)
                            .tag($0.symbol)
                    }
                }
                LabeledContent("Shortcut") {
                    VStack(alignment: .trailing, spacing: 4) {
                        ShortcutRecorder(hotkey: $draft.hotkey) { recording in
                            recording ? controller.suspendHotkeys() : controller.resumeHotkeys()
                        }
                        if let problem = controller.hotkeyProblems[draft.id] {
                            Label(problem, systemImage: "exclamationmark.triangle")
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
                            controller.copyLink(for: draft)
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .help("Copy this preset’s link for Shortcuts, Raycast or Terminal")
                    }
                }
            }

            ForEach(PresetFactory.deskOrder(of: draft.displays, displays: known), id: \.self) { uuid in
                if let target = binding(for: uuid) {
                    let detail = controller.displays.first { $0.id == uuid }
                    let name = detail?.known.displayName ?? target.wrappedValue.name
                    Section(name) {
                        TargetEditor(target: target, detail: detail, displayName: name)
                        Button("Remove from Preset", role: .destructive) {
                            draft = PresetFactory.removing(uuid, from: draft)
                        }
                        .buttonStyle(.borderless)
                        .accessibilityLabel("Remove \(name) from Preset")
                    }
                }
            }

            let missing = PresetFactory.missingDisplays(in: draft, from: known)
            if !missing.isEmpty {
                Section {
                    ForEach(missing) { display in
                        LabeledContent(display.displayName) {
                            Button("Add to Preset", systemImage: "plus.circle") {
                                draft = PresetFactory.adding(display, to: draft)
                            }
                            .accessibilityLabel("Add \(display.displayName) to Preset")
                        }
                    }
                } header: {
                    Text("Other Displays")
                } footer: {
                    Text("This preset leaves these displays alone until you add them.")
                }
            }

            Section {
                HStack {
                    Button("Apply Now") {
                        Task { appliedFromHere = await controller.apply(draft) }
                    }
                    .disabled(controller.isBusy)
                    Button("Update from Current Setup") {
                        controller.updateFromCurrentSetup(draft.id)
                        if let saved = controller.presets.first(where: { $0.id == draft.id }) { draft = saved }
                    }
                    .help("Replace these display settings with your current setup")
                    Spacer()
                    if controller.isBusy, let activity = controller.activity {
                        Text(activity)
                            .foregroundStyle(.secondary)
                        ProgressView()
                            .controlSize(.small)
                    }
                }
                if appliedFromHere, !controller.isBusy {
                    if controller.notices.isEmpty {
                        Label("Applied “\(draft.name)”.", systemImage: "checkmark.circle")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(controller.notices, id: \.self) { notice in
                            Label(notice, systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: draft) { _, updated in
            controller.update(updated)
            appliedFromHere = false
        }
        .onAppear {
            guard startRenaming else { return }
            isNameFocused = true
            controller.didStartEditing(draft.id)
        }
    }

    /// A binding that looks the target up by UUID each time, so removing a target never leaves a
    /// view holding a stale index.
    private func binding(for uuid: String) -> Binding<DisplayTarget>? {
        guard let target = draft.displays.first(where: { $0.uuid == uuid }) else { return nil }
        return Binding(
            get: { draft.displays.first { $0.uuid == uuid } ?? target },
            set: { updated in
                guard let index = draft.displays.firstIndex(where: { $0.uuid == uuid }) else { return }
                draft.displays[index] = updated
            }
        )
    }
}

private struct TargetEditor: View {
    @Binding var target: DisplayTarget
    let detail: DisplayDetail?
    /// Folded into accessibility labels: every display section has the same controls.
    let displayName: String

    private var options: [ResolutionOption] {
        ModeCatalogue.essentialOptions(from: detail?.options ?? [], keeping: target.mode)
    }

    var body: some View {
        Toggle("Switched on", isOn: $target.connected)
            .controlSize(.mini)
            .accessibilityLabel("\(displayName) switched on")

        if target.connected {
            Toggle("Set brightness", isOn: Binding(
                get: { target.brightness != nil },
                set: { target.brightness = $0 ? detail?.brightness ?? 0.5 : nil }
            ))
            .controlSize(.mini)
            .accessibilityLabel("Set brightness for \(displayName)")
            if let brightness = target.brightness {
                LabeledContent("Brightness") {
                    HStack {
                        Slider(value: Binding(get: { brightness }, set: { target.brightness = $0 }), in: 0...1) {
                            Text("Brightness, \(displayName)")
                        }
                        .labelsHidden()
                        .accessibilityValue(Text(brightness, format: .percent.precision(.fractionLength(0))))
                        Text(brightness, format: .percent.precision(.fractionLength(0)))
                            .monospacedDigit()
                            .frame(minWidth: 40, alignment: .trailing)
                            .accessibilityHidden(true)
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
