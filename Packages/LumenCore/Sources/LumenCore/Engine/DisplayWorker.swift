import CoreGraphics
import Dispatch
import Foundation

/// A display with the live values the UI shows.
public struct DisplayDetail: Hashable, Sendable, Identifiable {
    public var id: String { known.id }

    public var known: KnownDisplay
    /// `nil` when the display is off or its brightness cannot be read.
    public var brightness: Double?
    /// `nil` for the built-in display, displays that are off, and monitors without DDC contrast.
    public var contrast: Double?
    public var modes: [DisplayMode]
    public var currentMode: DisplayMode?
    /// `modes` grouped for pickers, computed once per snapshot rather than on every render.
    public let options: [ResolutionOption]

    public init(known: KnownDisplay, brightness: Double?, contrast: Double? = nil, modes: [DisplayMode], currentMode: DisplayMode?) {
        self.known = known
        self.brightness = brightness
        self.contrast = contrast
        self.modes = modes
        self.currentMode = currentMode
        self.options = ModeCatalogue.options(from: modes)
    }
}

public struct DisplaySnapshot: Sendable {
    /// The worker's records at the time of the snapshot; persist these.
    public var records: [DisplayRecord]
    public var displays: [DisplayDetail]
}

/// Runs every hardware operation off the main thread and owns the display records.
///
/// Backend calls block (disconnecting a display takes over a second), so the actor runs on its
/// own serial dispatch queue rather than the shared Swift concurrency thread pool.
///
/// Records live here, not with callers, and are updated step by step inside the actor. Calls
/// can still interleave while one is waiting for a display, but each sees the latest records,
/// so overlapping changes cannot overwrite each other.
public actor DisplayWorker {
    private let backend: any DisplayBackend
    private let onlineTimeout: Duration
    private let pollInterval: Duration
    private var records: [DisplayRecord]
    /// Displays switched off moments ago that CoreGraphics may still list.
    private var switchingOff: Set<String> = []
    private let queue = DispatchSerialQueue(label: "com.bsquared.lumen.display-worker", qos: .userInitiated)

    public nonisolated var unownedExecutor: UnownedSerialExecutor { queue.asUnownedSerialExecutor() }

    public init(
        backend: any DisplayBackend, records: [DisplayRecord] = [],
        onlineTimeout: Duration = .seconds(5), pollInterval: Duration = .milliseconds(250)
    ) {
        self.backend = backend
        self.records = records
        self.onlineTimeout = onlineTimeout
        self.pollInterval = pollInterval
    }

    // MARK: Reading

    public func snapshot() -> DisplaySnapshot {
        let displays = knownDisplays().map { display in
            guard display.status == .online else {
                return DisplayDetail(known: display, brightness: nil, modes: [], currentMode: nil)
            }
            let id = display.info.displayID
            let brightness = try? backend.brightness(of: display.info)
            // A monitor that didn't answer DDC for brightness won't for contrast either, and each
            // unanswered query costs a few hundred milliseconds of retries.
            let contrast = display.info.isBuiltin || brightness == nil ? nil : try? backend.contrast(of: display.info)
            return DisplayDetail(
                known: display, brightness: brightness, contrast: contrast,
                modes: backend.modes(of: id), currentMode: backend.currentMode(of: id)
            )
        }
        return DisplaySnapshot(records: records, displays: displays)
    }

    // MARK: Single changes

    public func setConnected(_ connected: Bool, uuid: String) async -> RunReport {
        var report = RunReport()
        if connected {
            guard let display = knownDisplays().first(where: { $0.id == uuid }), display.status == .disconnected else { return report }
            var unreachable = Set<String>()
            connect(display.info, report: &report, unreachable: &unreachable)
            if unreachable.isEmpty {
                report.failures += await waitForOnline([uuid]).map { _ in DisplayFailure(name: display.displayName, reason: .didNotComeBack) }
            }
        } else {
            await disconnect(uuid, report: &report)
        }
        _ = knownDisplays()
        return report
    }

    /// Throws so the UI can show why a monitor ignored the slider.
    /// Gives a display a friendlier name. Blank restores the hardware name.
    public func rename(uuid: String, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        records = records.map { record in
            guard record.id == uuid else { return record }
            var renamed = record
            renamed.customName = trimmed.isEmpty ? nil : trimmed
            return renamed
        }
    }

    public func setBrightness(_ value: Double, uuid: String) throws {
        guard let info = onlineInfo(uuid) else { return }
        try backend.setBrightness(value, of: info)
    }

    public func setContrast(_ value: Double, uuid: String) throws {
        guard let info = onlineInfo(uuid) else { return }
        try backend.setContrast(value, of: info)
    }

    public func setMode(_ mode: DisplayMode, uuid: String) throws {
        guard let info = onlineInfo(uuid) else { return }
        try backend.setMode(mode, displayID: info.displayID)
    }

    public func reconnectAll() async -> RunReport {
        let offline = knownDisplays().filter { $0.status == .disconnected }
        var report = RunReport()
        var unreachable = Set<String>()

        for display in offline {
            connect(display.info, report: &report, unreachable: &unreachable)
        }
        let missing = await waitForOnline(offline.map(\.id).filter { !unreachable.contains($0) })
        report.failures += missing.map { DisplayFailure(name: name(of: $0), reason: .didNotComeBack) }
        _ = knownDisplays()
        return report
    }

    // MARK: Presets

    public func apply(_ preset: Preset) async -> RunReport {
        let plan = PresetPlanner.plan(preset, displays: knownDisplays())
        var report = RunReport(skipped: plan.skipped)
        var unreachable = Set<String>()

        for step in plan.steps {
            switch step {
            case .connect(let uuid):
                guard let record = records.first(where: { $0.id == uuid }) else { continue }
                connect(record.info, report: &report, unreachable: &unreachable)

            case .waitForOnline(let uuids):
                for uuid in await waitForOnline(uuids.filter { !unreachable.contains($0) }) {
                    unreachable.insert(uuid)
                    report.failures.append(DisplayFailure(name: name(of: uuid), reason: .didNotComeBack))
                }

            case .setMode(let uuid, let mode):
                guard !unreachable.contains(uuid) else { continue }
                change(uuid, report: &report) { try backend.setMode(mode, displayID: $0.displayID) }

            case .setBrightness(let uuid, let value):
                guard !unreachable.contains(uuid) else { continue }
                change(uuid, report: &report) { try backend.setBrightness(value, of: $0) }

            case .disconnect(let uuid):
                await disconnect(uuid, report: &report)
            }
        }
        _ = knownDisplays()
        return report
    }

    // MARK: Steps

    /// Merges what is online now into the records and resolves every display's status.
    private func knownDisplays() -> [KnownDisplay] {
        let online = backend.onlineDisplays()
        records = DisplayRegistry.merge(records: records, online: online, keepingFlagsFor: switchingOff)
        return DisplayRegistry.knownDisplays(
            records: records, online: online, framebuffers: backend.attachedFramebuffers(), switchingOff: switchingOff
        )
    }

    private func connect(_ info: DisplayInfo, report: inout RunReport, unreachable: inout Set<String>) {
        do {
            try backend.setEnabled(true, displayID: info.displayID)
        } catch {
            unreachable.insert(info.uuid)
            report.failures.append(.backend(name(of: info.uuid), error))
        }
    }

    /// Disconnects when it is safe to at this moment, then waits for the display to leave the
    /// online list. The record is flagged before the call because a switched-off display
    /// vanishes from CoreGraphics, and un-flagged if the call fails.
    private func disconnect(_ uuid: String, report: inout RunReport) async {
        let known = knownDisplays()
        guard let display = known.first(where: { $0.id == uuid }), display.status == .online else { return }
        guard SafetyRules.canDisconnect(uuid, in: known) else {
            report.skipped.append(.wouldLeaveNoDisplay(name: display.displayName))
            return
        }

        records = DisplayRegistry.setDisconnectedByLumen(true, uuid: uuid, in: records)
        switchingOff.insert(uuid)
        defer { switchingOff.remove(uuid) }
        do {
            try backend.setEnabled(false, displayID: display.info.displayID)
        } catch {
            records = DisplayRegistry.setDisconnectedByLumen(false, uuid: uuid, in: records)
            report.failures.append(.backend(display.displayName, error))
            return
        }
        await waitUntil { !$0.contains(uuid) }
    }

    private func change(_ uuid: String, report: inout RunReport, _ body: (DisplayInfo) throws -> Void) {
        guard let info = onlineInfo(uuid) else {
            report.failures.append(DisplayFailure(name: name(of: uuid), reason: .notOnline))
            return
        }
        do {
            try body(info)
        } catch {
            report.failures.append(.backend(name(of: uuid), error))
        }
    }

    /// Polls until every display is online, returning the ones that never appeared.
    private func waitForOnline(_ uuids: [String]) async -> [String] {
        guard !uuids.isEmpty else { return [] }
        await waitUntil { online in uuids.allSatisfy(online.contains) }
        let online = Set(backend.onlineDisplays().map(\.uuid))
        return uuids.filter { !online.contains($0) }
    }

    /// Polls the online display UUIDs until `condition` holds, the timeout passes or the task is
    /// cancelled.
    private func waitUntil(_ condition: (Set<String>) -> Bool) async {
        let clock = ContinuousClock()
        let deadline = clock.now + onlineTimeout
        while !Task.isCancelled, clock.now < deadline {
            if condition(Set(backend.onlineDisplays().map(\.uuid))) { return }
            try? await Task.sleep(for: pollInterval)
        }
    }

    private func onlineInfo(_ uuid: String) -> DisplayInfo? {
        guard !switchingOff.contains(uuid) else { return nil }
        return backend.onlineDisplays().first { $0.uuid == uuid }
    }

    private func name(of uuid: String) -> String {
        guard let record = records.first(where: { $0.id == uuid }) else { return "A display" }
        return record.customName ?? record.info.name
    }
}
