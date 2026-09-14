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
    /// Messages from the last action, shown under the display cards.
    private(set) var notices: [String] = []
    /// Why a monitor ignored the brightness slider, by display UUID.
    private(set) var brightnessErrors: [String: String] = [:]
    private(set) var isBusy = false
    /// The preset applied most recently, until the user changes something by hand.
    private(set) var activePresetID: Preset.ID?
    private(set) var hotkeyProblems: [Preset.ID: String] = [:]

    @ObservationIgnored private let store: StateStore
    @ObservationIgnored private let worker: DisplayWorker
    @ObservationIgnored private var coalescer: BrightnessCoalescer?
    @ObservationIgnored private let hotkeys = HotkeyCenter()
    @ObservationIgnored private var records: [DisplayRecord]
    @ObservationIgnored private var lastSaved: LumenState?
    /// False when an unreadable settings file could not be moved aside, so it is never
    /// overwritten.
    @ObservationIgnored private var canPersist: Bool
    /// A display change arrived during an action and still needs a refresh.
    @ObservationIgnored private var needsRefresh = false
    @ObservationIgnored private var observation: Task<Void, Never>?
    @ObservationIgnored private var pendingRefresh: Task<Void, Never>?
    @ObservationIgnored private var started = false

    init(backend: any DisplayBackend = SystemDisplayBackend(), store: StateStore = .applicationSupport()) {
        let loaded = Self.loadState(from: store)
        let worker = DisplayWorker(backend: backend, records: loaded.state?.displays ?? [])
        self.store = store
        self.worker = worker
        self.records = loaded.state?.displays ?? []
        self.presets = loaded.state?.presets ?? []
        self.lastSaved = loaded.state
        self.notices = loaded.notices
        self.canPersist = loaded.canPersist
        self.coalescer = BrightnessCoalescer { [weak self] uuid, value in
            do {
                try await worker.setBrightness(value, uuid: uuid)
                await self?.setBrightnessError(nil, for: uuid)
            } catch {
                await self?.setBrightnessError(error.localizedDescription, for: uuid)
            }
        }
    }

    var visibleDisplays: [DisplayDetail] { displays.filter { $0.known.status != .unavailable } }
    var hasDisconnectedDisplays: Bool { displays.contains { $0.known.status == .disconnected } }
    var menuBarSymbol: String { presets.first { $0.id == activePresetID }?.symbol ?? "sun.max" }

    // MARK: Lifecycle

    func start() async {
        guard !started else { return }
        started = true
        await refresh()

        if presets.isEmpty {
            let builtin = displays.first { $0.known.info.isBuiltin }
            presets = PresetFactory.seedPresets(from: displays.map(\.known), builtinBrightness: builtin?.brightness)
            persist()
        }
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
        activePresetID = nil
        await run { [worker] in await worker.setConnected(connected, uuid: uuid) }
    }

    func setBrightness(_ value: Double, for uuid: String) {
        activePresetID = nil
        if let index = displays.firstIndex(where: { $0.id == uuid }) {
            displays[index].brightness = value
        }
        guard let coalescer else { return }
        Task { await coalescer.submit(uuid: uuid, value: value) }
    }

    func select(_ option: ResolutionOption, refreshRate: Double?, for uuid: String) async {
        guard !isBusy,
              let detail = displays.first(where: { $0.id == uuid }),
              let rate = refreshRate ?? ModeCatalogue.preferredRefreshRate(for: option, current: detail.currentMode?.refreshRate),
              let mode = ModeCatalogue.mode(for: option, refreshRate: rate, in: detail.modes)
        else { return }

        activePresetID = nil
        await run { [worker] in
            do {
                try await worker.setMode(mode, uuid: uuid)
                return RunReport()
            } catch {
                return RunReport(failures: [DisplayFailure(name: detail.known.info.name, reason: .backend(error.localizedDescription))])
            }
        }
    }

    func reconnectAll() async {
        guard !isBusy else { return }
        activePresetID = nil
        await run { [worker] in await worker.reconnectAll() }
    }

    // MARK: Presets

    func apply(_ preset: Preset) async {
        guard let report = await run({ [worker] in await worker.apply(preset) }) else { return }
        activePresetID = report.failures.isEmpty ? preset.id : nil
    }

    func apply(presetID: Preset.ID) async {
        guard let preset = presets.first(where: { $0.id == presetID }) else { return }
        await apply(preset)
    }

    @discardableResult
    func saveCurrentAsPreset(named name: String) -> Preset {
        let preset = PresetFactory.capture(name: name, symbol: "display.2", displays: capturedDisplays())
        presets.append(preset)
        persist()
        return preset
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

    func delete(_ presetID: Preset.ID) {
        presets.removeAll { $0.id == presetID }
        if activePresetID == presetID { activePresetID = nil }
        persist()
        registerHotkeys()
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
    private func run(_ operation: () async -> RunReport) async -> RunReport? {
        guard !isBusy else { return nil }
        isBusy = true
        let report = await operation()
        notices = report.messages
        await refresh()
        isBusy = false

        if needsRefresh {
            needsRefresh = false
            scheduleRefresh()
        }
        return report
    }

    private func setBrightnessError(_ message: String?, for uuid: String) {
        guard brightnessErrors[uuid] != message else { return }
        brightnessErrors[uuid] = message
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
        let state = LumenState(displays: records, presets: presets)
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
