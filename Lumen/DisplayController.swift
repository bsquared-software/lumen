import Foundation
import LumenCore
import Observation

/// The app's single source of truth: display state for the UI, presets, and every user
/// action. Hardware work is delegated to `DisplayWorker`, which runs off the main thread.
@MainActor
@Observable
final class DisplayController {
    private(set) var displays: [DisplayDetail] = []
    private(set) var presets: [Preset] = []
    /// Messages from the last action, shown under the display cards.
    private(set) var notices: [String] = []
    private(set) var isBusy = false
    /// The preset applied most recently, until the user changes something by hand.
    private(set) var activePresetID: Preset.ID?
    private(set) var hotkeyProblems: [Preset.ID: String] = [:]

    @ObservationIgnored private var records: [DisplayRecord] = []
    @ObservationIgnored private let store: StateStore
    @ObservationIgnored private let worker: DisplayWorker
    @ObservationIgnored private let coalescer: BrightnessCoalescer
    @ObservationIgnored private let hotkeys = HotkeyCenter()
    @ObservationIgnored private var observation: Task<Void, Never>?
    @ObservationIgnored private var pendingRefresh: Task<Void, Never>?
    @ObservationIgnored private var started = false

    init(backend: any DisplayBackend = SystemDisplayBackend(), store: StateStore = .applicationSupport()) {
        let worker = DisplayWorker(backend: backend)
        self.store = store
        self.worker = worker
        self.coalescer = BrightnessCoalescer { uuid, value in
            try? await worker.setBrightness(value, uuid: uuid)
        }
    }

    var visibleDisplays: [DisplayDetail] { displays.filter { $0.known.status != .unavailable } }
    var hasDisconnectedDisplays: Bool { displays.contains { $0.known.status == .disconnected } }
    var menuBarSymbol: String { presets.first { $0.id == activePresetID }?.symbol ?? "sun.max" }

    // MARK: Lifecycle

    func start() async {
        guard !started else { return }
        started = true
        loadState()
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
        let snapshot = await worker.snapshot(records: records)
        records = snapshot.records
        displays = snapshot.displays
        persist()
    }

    // MARK: Display actions

    func setConnected(_ connected: Bool, _ uuid: String) async {
        activePresetID = nil
        await run { [records, worker] in await worker.setConnected(connected, uuid: uuid, records: records) }
    }

    func setBrightness(_ value: Double, for uuid: String) {
        activePresetID = nil
        if let index = displays.firstIndex(where: { $0.id == uuid }) {
            displays[index].brightness = value
        }
        Task { await coalescer.submit(uuid: uuid, value: value) }
    }

    func select(_ option: ResolutionOption, refreshRate: Double?, for uuid: String) async {
        guard let detail = displays.first(where: { $0.id == uuid }),
              let rate = refreshRate ?? ModeCatalogue.preferredRefreshRate(for: option, current: detail.currentMode?.refreshRate),
              let mode = ModeCatalogue.mode(for: option, refreshRate: rate, in: detail.modes)
        else { return }

        activePresetID = nil
        do {
            try await worker.setMode(mode, uuid: uuid)
            notices = []
        } catch {
            notices = ["\(detail.known.info.name): \(error.localizedDescription)"]
        }
        await refresh()
    }

    func reconnectAll() async {
        activePresetID = nil
        await run { [records, worker] in await worker.reconnectAll(records: records) }
    }

    // MARK: Presets

    func apply(_ preset: Preset) async {
        guard !isBusy else { return }
        await run { [records, worker] in await worker.apply(preset, records: records) }
        activePresetID = preset.id
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
        presets[index].displays = PresetFactory.capture(name: "", symbol: "", displays: capturedDisplays()).displays
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

    private func run(_ operation: () async -> WorkerResult) async {
        isBusy = true
        defer { isBusy = false }
        let result = await operation()
        records = result.records
        notices = result.report.messages
        await refresh()
    }

    private func capturedDisplays() -> [CapturedDisplay] {
        displays.map { CapturedDisplay(display: $0.known, brightness: $0.brightness, mode: $0.currentMode) }
    }

    private func loadState() {
        do {
            guard let state = try store.load() else { return }
            records = state.displays
            presets = state.presets
        } catch {
            let moved = try? store.quarantineCorruptFile()
            notices = ["Lumen couldn’t read its saved settings, so it started fresh."
                + (moved.map { " The old file is at \($0.path)." } ?? "")]
        }
    }

    private func persist() {
        do {
            try store.save(LumenState(displays: records, presets: presets))
        } catch {
            notices = ["Lumen couldn’t save its settings: \(error.localizedDescription)"]
        }
    }

    /// Display changes arrive in bursts of callbacks; refresh once they settle.
    private func observeReconfiguration() {
        observation = Task { [weak self] in
            for await _ in DisplayReconfigurationObserver.changes() {
                guard let self else { return }
                self.pendingRefresh?.cancel()
                self.pendingRefresh = Task {
                    try? await Task.sleep(for: .milliseconds(400))
                    guard !Task.isCancelled, !self.isBusy else { return }
                    await self.refresh()
                }
            }
        }
    }
}
