import AppKit
import Foundation
import LumenCore
import Observation

/// The app's single source of truth for the UI: display state, presets and every user action.
/// Hardware work and the display records live in `DisplayWorker`, off the main thread.
@MainActor
@Observable
final class DisplayController {
    private(set) var displays: [DisplayDetail] = []
    private(set) var presets: [Preset] = []
    /// Messages from the last action, shown under the display cards until dismissed.
    private(set) var notices: [String] = []
    /// Why a monitor ignored a brightness or contrast slider, by display UUID.
    private(set) var adjustmentErrors: [String: String] = [:]
    private(set) var isBusy = false
    /// What the current action is doing, e.g. "Applying Night…".
    private(set) var activity: String?
    /// The preset applied most recently, until the user changes something by hand.
    private(set) var activePresetID: Preset.ID?
    private(set) var hotkeyProblems: [Preset.ID: String] = [:]
    /// Incremented to ask the always-visible menu bar label to open Settings.
    private(set) var settingsRequest = 0
    /// A preset Settings should select and start renaming, set when one is created from the popover.
    private(set) var presetToEdit: Preset.ID?
    /// Shown once in the popover: without opening at login, shortcuts stop working after a restart.
    private(set) var isOfferingLoginItem = false

    @ObservationIgnored private let store: StateStore
    @ObservationIgnored private let worker: DisplayWorker
    @ObservationIgnored private var brightness: AdjustmentCoalescer?
    @ObservationIgnored private var contrast: AdjustmentCoalescer?
    @ObservationIgnored private let hotkeys = HotkeyCenter()
    @ObservationIgnored private var records: [DisplayRecord]
    @ObservationIgnored private var lastSaved: LumenState?
    /// False when an unreadable settings file could not be moved aside, so it is never
    /// overwritten.
    @ObservationIgnored private var canPersist: Bool
    /// A display change arrived during an action and still needs a refresh.
    @ObservationIgnored private var needsRefresh = false
    @ObservationIgnored private var hasOfferedLoginItem: Bool
    @ObservationIgnored private var startup: Task<Void, Never>?
    @ObservationIgnored private var observation: Task<Void, Never>?
    @ObservationIgnored private var pendingRefresh: Task<Void, Never>?

    init(backend: any DisplayBackend = SystemDisplayBackend(), store: StateStore = .applicationSupport()) {
        let loaded = Self.loadState(from: store)
        let worker = DisplayWorker(backend: backend, records: loaded.state?.displays ?? [])
        self.store = store
        self.worker = worker
        self.records = loaded.state?.displays ?? []
        self.presets = loaded.state?.presets ?? []
        self.activePresetID = loaded.state?.activePresetID
        self.lastSaved = loaded.state
        self.notices = loaded.notices
        self.canPersist = loaded.canPersist
        self.hasOfferedLoginItem = loaded.state?.hasOfferedLoginItem ?? false
        self.brightness = makeCoalescer { worker, uuid, value in try await worker.setBrightness(value, uuid: uuid) }
        self.contrast = makeCoalescer { worker, uuid, value in try await worker.setContrast(value, uuid: uuid) }
    }

    /// Slider writes, coalesced, with any failure shown on the display's card.
    private func makeCoalescer(_ write: @escaping @Sendable (DisplayWorker, String, Double) async throws -> Void) -> AdjustmentCoalescer {
        AdjustmentCoalescer { [weak self, worker] uuid, value in
            do {
                try await write(worker, uuid, value)
                await self?.setAdjustmentError(nil, for: uuid)
            } catch {
                await self?.setAdjustmentError(error.localizedDescription, for: uuid)
            }
        }
    }

    var visibleDisplays: [DisplayDetail] { displays.filter { $0.known.status != .unavailable } }
    var hasDisconnectedDisplays: Bool { displays.contains { $0.known.status == .disconnected } }
    var menuBarSymbol: String { presets.first { $0.id == activePresetID }?.symbol ?? "sun.max" }

    // MARK: Lifecycle

    /// Safe to call more than once; later callers wait for the first start to finish.
    func start() async {
        if let startup { return await startup.value }
        let startup = Task { await performStart() }
        self.startup = startup
        await startup.value
    }

    private func performStart() async {
        await refresh()

        if presets.isEmpty {
            let builtin = displays.first { $0.known.info.isBuiltin }
            presets = PresetFactory.seedPresets(from: displays.map(\.known), builtinBrightness: builtin?.brightness)
        }
        // A remembered preset only stays active if the displays still match it, e.g. not after a
        // restart brought the monitors back.
        if let preset = presets.first(where: { $0.id == activePresetID }),
           !PresetPlanner.connectionsMatch(preset, displays: displays.map(\.known)) {
            activePresetID = nil
        }
        isOfferingLoginItem = !hasOfferedLoginItem && !LoginItem.isEnabled
        persist()
        registerHotkeys()
        observeReconfiguration()
    }

    func refresh() async {
        let snapshot = await worker.snapshot()
        displays = snapshot.displays
        records = snapshot.records
        persist()
    }

    // MARK: Display actions

    func setConnected(_ connected: Bool, _ uuid: String) async {
        guard !isBusy else { return }
        markActive(nil)
        let name = displayName(uuid)
        await run(connected ? "Switching on \(name)…" : "Switching off \(name)…") { [worker] in
            await worker.setConnected(connected, uuid: uuid)
        }
    }

    func setBrightness(_ value: Double, for uuid: String) {
        markActive(nil)
        if let index = displays.firstIndex(where: { $0.id == uuid }) {
            displays[index].brightness = value
        }
        guard let brightness else { return }
        Task { await brightness.submit(uuid: uuid, value: value) }
    }

    func setContrast(_ value: Double, for uuid: String) {
        if let index = displays.firstIndex(where: { $0.id == uuid }) {
            displays[index].contrast = value
        }
        guard let contrast else { return }
        Task { await contrast.submit(uuid: uuid, value: value) }
    }

    func select(_ option: ResolutionOption, refreshRate: Double?, for uuid: String) async {
        guard !isBusy,
              let detail = displays.first(where: { $0.id == uuid }),
              let rate = refreshRate ?? ModeCatalogue.preferredRefreshRate(for: option, current: detail.currentMode?.refreshRate),
              let mode = ModeCatalogue.mode(for: option, refreshRate: rate, in: detail.modes)
        else { return }

        markActive(nil)
        await run("Changing \(detail.known.displayName) to \(option.label)…") { [worker] in
            do {
                try await worker.setMode(mode, uuid: uuid)
                return RunReport()
            } catch {
                return RunReport(failures: [DisplayFailure(name: detail.known.displayName, reason: .backend(error.localizedDescription))])
            }
        }
    }

    func reconnectAll() async {
        guard !isBusy else { return }
        markActive(nil)
        await run("Reconnecting displays…") { [worker] in await worker.reconnectAll() }
    }

    func rename(_ uuid: String, to name: String) async {
        await worker.rename(uuid: uuid, to: name)
        await refresh()
    }

    func forget(_ uuid: String) async {
        await worker.forget(uuid: uuid)
        await refresh()
    }

    /// Waits for any running action, then switches back on every display Lumen switched off.
    func prepareToQuit() async {
        let deadline = ContinuousClock.now + .seconds(10)
        while isBusy, ContinuousClock.now < deadline {
            try? await Task.sleep(for: .milliseconds(100))
        }
        guard hasDisconnectedDisplays else { return }
        await reconnectAll()
    }

    func acceptLoginItem() {
        do {
            try LoginItem.setEnabled(true)
            if LoginItem.needsApproval {
                notices = ["Allow Lumen in System Settings › General › Login Items to finish."]
                LoginItem.openSystemSettings()
            }
        } catch {
            notices = ["Lumen couldn’t add itself to Login Items: \(error.localizedDescription)"]
        }
        finishLoginItemOffer()
    }

    func declineLoginItem() {
        finishLoginItemOffer()
    }

    private func finishLoginItemOffer() {
        isOfferingLoginItem = false
        hasOfferedLoginItem = true
        persist()
    }

    func dismissNotices() {
        guard !notices.isEmpty else { return }
        notices = []
    }

    // MARK: Presets

    /// Returns `false` when another action was running, so nothing happened.
    @discardableResult
    func apply(_ preset: Preset) async -> Bool {
        guard let report = await run("Applying \(preset.name)…", { [worker] in await worker.apply(preset) }) else { return false }
        markActive(report.failures.isEmpty ? preset.id : nil)
        return true
    }

    func apply(presetID: Preset.ID) async {
        guard let preset = presets.first(where: { $0.id == presetID }) else { return }
        await apply(preset)
    }

    /// Handles `lumen://apply/<preset>` and `lumen://reconnect-all`.
    func open(_ url: URL) async {
        await start()
        switch PresetLink.action(for: url, in: presets) {
        case .success(.apply(let preset)):
            await apply(preset)
        case .success(.reconnectAll):
            await reconnectAll()
        case .failure(let error):
            notices = [error.message]
        }
    }

    func link(for preset: Preset) -> URL {
        PresetLink.url(for: preset)
    }

    func copyLink(for preset: Preset) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(link(for: preset).absoluteString, forType: .string)
    }

    /// Inserts a copy after the original and returns it.
    @discardableResult
    func duplicate(_ presetID: Preset.ID) -> Preset? {
        guard let index = presets.firstIndex(where: { $0.id == presetID }) else { return nil }
        let copy = PresetFactory.duplicate(presets[index], existingNames: presets.map(\.name))
        presets.insert(copy, at: index + 1)
        persist()
        return copy
    }

    @discardableResult
    func saveCurrentAsPreset() -> Preset {
        let name = PresetFactory.uniqueName("New Preset", existing: presets.map(\.name))
        let preset = PresetFactory.capture(name: name, symbol: "display.2", displays: capturedDisplays())
        presets.append(preset)
        persist()
        presetToEdit = preset.id
        return preset
    }

    /// From the popover: save the setup, then open Settings on the new preset to name it.
    func saveCurrentSetupAndEdit() {
        saveCurrentAsPreset()
        requestSettings()
    }

    func didStartEditing(_ presetID: Preset.ID) {
        if presetToEdit == presetID { presetToEdit = nil }
    }

    func updateFromCurrentSetup(_ presetID: Preset.ID) {
        guard let index = presets.firstIndex(where: { $0.id == presetID }) else { return }
        presets[index] = PresetFactory.updating(presets[index], from: capturedDisplays())
        persist()
    }

    func update(_ preset: Preset) {
        guard let index = presets.firstIndex(where: { $0.id == preset.id }), presets[index] != preset else { return }
        let hotkeyChanged = presets[index].hotkey != preset.hotkey
        presets[index] = preset
        persist()
        if hotkeyChanged { registerHotkeys() }
    }

    func reorderPresets(_ reordered: [Preset]) {
        guard reordered.map(\.id) != presets.map(\.id), Set(reordered.map(\.id)) == Set(presets.map(\.id)) else { return }
        presets = reordered
        persist()
    }

    func delete(_ presetID: Preset.ID) {
        presets.removeAll { $0.id == presetID }
        if activePresetID == presetID { activePresetID = nil }
        persist()
        registerHotkeys()
    }

    func requestSettings() {
        settingsRequest += 1
    }

    // MARK: Hotkeys

    /// Called while a shortcut is being recorded, so pressing an existing shortcut records it
    /// instead of applying a preset.
    func suspendHotkeys() {
        hotkeys.unregisterAll()
    }

    func resumeHotkeys() {
        registerHotkeys()
    }

    private func registerHotkeys() {
        let entries = presets.compactMap { preset in preset.hotkey.map { (preset.id, $0) } }
        hotkeyProblems = hotkeys.register(entries) { [weak self] presetID in
            Task { await self?.apply(presetID: presetID) }
        }
    }

    // MARK: Private

    /// Runs one action at a time. Returns `nil` without doing anything if another is running.
    @discardableResult
    private func run(_ description: String, _ operation: () async -> RunReport) async -> RunReport? {
        guard !isBusy else { return nil }
        isBusy = true
        activity = description
        let report = await operation()
        notices = report.messages
        await refresh()
        activity = nil
        isBusy = false

        if needsRefresh {
            needsRefresh = false
            scheduleRefresh()
        }
        return report
    }

    private func markActive(_ presetID: Preset.ID?) {
        guard activePresetID != presetID else { return }
        activePresetID = presetID
        persist()
    }

    private func setAdjustmentError(_ message: String?, for uuid: String) {
        guard adjustmentErrors[uuid] != message else { return }
        adjustmentErrors[uuid] = message
    }

    private func displayName(_ uuid: String) -> String {
        displays.first { $0.id == uuid }?.known.displayName ?? "display"
    }

    private func capturedDisplays() -> [CapturedDisplay] {
        displays.map { CapturedDisplay(display: $0.known, brightness: $0.brightness, mode: $0.currentMode) }
    }

    private nonisolated static func loadState(from store: StateStore) -> (state: LumenState?, notices: [String], canPersist: Bool) {
        do {
            return (try store.load(), [], true)
        } catch {
            do {
                let moved = try store.quarantineCorruptFile()
                return (nil, ["Lumen couldn’t read its saved settings, so it started fresh. The old file is at \(moved.path)."], true)
            } catch {
                return (nil, ["Lumen couldn’t read its saved settings at \(store.fileURL.path). Changes won’t be saved until that file is fixed or removed."], false)
            }
        }
    }

    private func persist() {
        let state = LumenState(
            displays: records, presets: presets, activePresetID: activePresetID, hasOfferedLoginItem: hasOfferedLoginItem ? true : nil
        )
        guard canPersist, state != lastSaved else { return }
        do {
            try store.save(state)
            lastSaved = state
        } catch {
            notices = ["Lumen couldn’t save its settings: \(error.localizedDescription)"]
        }
    }

    /// Display changes arrive in bursts of callbacks. Refresh once they settle, or after the
    /// current action if one is running.
    private func observeReconfiguration() {
        observation = Task { [weak self] in
            for await _ in DisplayReconfigurationObserver.changes() {
                guard let self else { return }
                if self.isBusy {
                    self.needsRefresh = true
                } else {
                    self.scheduleRefresh()
                }
            }
        }
    }

    private func scheduleRefresh() {
        pendingRefresh?.cancel()
        pendingRefresh = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled, let self else { return }
            if self.isBusy {
                self.needsRefresh = true
            } else {
                await self.refresh()
            }
        }
    }
}
