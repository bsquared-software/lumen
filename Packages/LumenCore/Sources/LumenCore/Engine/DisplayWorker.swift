import CoreGraphics
import Dispatch

/// A display with the live values the UI shows.
public struct DisplayDetail: Hashable, Sendable, Identifiable {
    public var id: String { known.id }

    public var known: KnownDisplay
    /// `nil` when the display is off or its brightness cannot be read.
    public var brightness: Double?
    public var modes: [DisplayMode]
    public var currentMode: DisplayMode?

    public init(known: KnownDisplay, brightness: Double?, modes: [DisplayMode], currentMode: DisplayMode?) {
        self.known = known
        self.brightness = brightness
        self.modes = modes
        self.currentMode = currentMode
    }
}

public struct DisplaySnapshot: Sendable {
    /// Records merged with what is online now; persist these.
    public var records: [DisplayRecord]
    public var displays: [DisplayDetail]
}

public struct WorkerResult: Sendable {
    public var records: [DisplayRecord]
    public var report: RunReport
}

/// Runs every hardware operation, one at a time, off the main thread.
///
/// Backend calls block (disconnecting a display takes over a second), so the actor runs on its
/// own serial dispatch queue rather than the shared Swift concurrency thread pool. The worker
/// is stateless: callers pass the display records in and persist the records that come back.
public actor DisplayWorker {
    private let backend: any DisplayBackend
    private let onlineTimeout: Duration
    private let pollInterval: Duration
    private let queue = DispatchSerialQueue(label: "com.bsquared.lumen.display-worker", qos: .userInitiated)

    public nonisolated var unownedExecutor: UnownedSerialExecutor { queue.asUnownedSerialExecutor() }

    public init(backend: any DisplayBackend, onlineTimeout: Duration = .seconds(5), pollInterval: Duration = .milliseconds(250)) {
        self.backend = backend
        self.onlineTimeout = onlineTimeout
        self.pollInterval = pollInterval
    }

    // MARK: Reading

    public func snapshot(records: [DisplayRecord]) -> DisplaySnapshot {
        let online = backend.onlineDisplays()
        let merged = DisplayRegistry.merge(records: records, online: online)
        let displays = DisplayRegistry.knownDisplays(records: merged, online: online).map { display in
            guard display.status == .online else {
                return DisplayDetail(known: display, brightness: nil, modes: [], currentMode: nil)
            }
            let id = display.info.displayID
            return DisplayDetail(
                known: display,
                brightness: try? backend.brightness(of: display.info),
                modes: backend.modes(of: id),
                currentMode: backend.currentMode(of: id)
            )
        }
        return DisplaySnapshot(records: merged, displays: displays)
    }

    // MARK: Single changes

    public func setConnected(_ connected: Bool, uuid: String, records: [DisplayRecord]) async -> WorkerResult {
        var records = DisplayRegistry.merge(records: records, online: backend.onlineDisplays())
        var report = RunReport()

        if connected {
            var unreachable = Set<String>()
            connect(uuid, records: records, report: &report, unreachable: &unreachable)
            if unreachable.isEmpty {
                let missing = await waitForOnline([uuid])
                report.failures += missing.map { DisplayFailure(name: name(of: $0, in: records), reason: .didNotComeBack) }
            }
        } else {
            records = disconnect(uuid, records: records, report: &report)
        }
        return finish(records, report)
    }

    public func setBrightness(_ value: Double, uuid: String) throws {
        guard let info = onlineInfo(uuid) else { return }
        try backend.setBrightness(value, of: info)
    }

    public func setMode(_ mode: DisplayMode, uuid: String) throws {
        guard let info = onlineInfo(uuid) else { return }
        try backend.setMode(mode, displayID: info.displayID)
    }

    public func reconnectAll(records: [DisplayRecord]) async -> WorkerResult {
        let online = backend.onlineDisplays()
        let records = DisplayRegistry.merge(records: records, online: online)
        let offline = DisplayRegistry.knownDisplays(records: records, online: online).filter { $0.status == .disconnected }
        var report = RunReport()
        var unreachable = Set<String>()

        for display in offline {
            connect(display.id, records: records, report: &report, unreachable: &unreachable)
        }
        let missing = await waitForOnline(offline.map(\.id).filter { !unreachable.contains($0) })
        report.failures += missing.map { DisplayFailure(name: name(of: $0, in: records), reason: .didNotComeBack) }
        return finish(records, report)
    }

    // MARK: Presets

    public func apply(_ preset: Preset, records: [DisplayRecord]) async -> WorkerResult {
        let online = backend.onlineDisplays()
        var records = DisplayRegistry.merge(records: records, online: online)
        let plan = PresetPlanner.plan(preset, displays: DisplayRegistry.knownDisplays(records: records, online: online))
        var report = RunReport(skipped: plan.skipped)
        var unreachable = Set<String>()

        for step in plan.steps {
            switch step {
            case .connect(let uuid):
                connect(uuid, records: records, report: &report, unreachable: &unreachable)

            case .waitForOnline(let uuids):
                let missing = await waitForOnline(uuids.filter { !unreachable.contains($0) })
                for uuid in missing {
                    unreachable.insert(uuid)
                    report.failures.append(DisplayFailure(name: name(of: uuid, in: records), reason: .didNotComeBack))
                }

            case .setMode(let uuid, let mode):
                guard !unreachable.contains(uuid) else { continue }
                change(uuid, records: records, report: &report) { try backend.setMode(mode, displayID: $0.displayID) }

            case .setBrightness(let uuid, let value):
                guard !unreachable.contains(uuid) else { continue }
                change(uuid, records: records, report: &report) { try backend.setBrightness(value, of: $0) }

            case .disconnect(let uuid):
                records = disconnect(uuid, records: records, report: &report)
            }
        }
        return finish(records, report)
    }

    // MARK: Steps

    private func connect(_ uuid: String, records: [DisplayRecord], report: inout RunReport, unreachable: inout Set<String>) {
        guard let record = records.first(where: { $0.id == uuid }) else { return }
        do {
            try backend.setEnabled(true, displayID: record.info.displayID)
        } catch {
            unreachable.insert(uuid)
            report.failures.append(.backend(record.info.name, error))
        }
    }

    /// Disconnects when it is safe. The record is flagged before the call because a
    /// disconnected display vanishes from CoreGraphics, and un-flagged again if the call fails.
    private func disconnect(_ uuid: String, records: [DisplayRecord], report: inout RunReport) -> [DisplayRecord] {
        let online = backend.onlineDisplays()
        guard let info = online.first(where: { $0.uuid == uuid && $0.isActive }) else { return records }
        guard SafetyRules.canDisconnect(uuid, in: DisplayRegistry.knownDisplays(records: records, online: online)) else {
            report.skipped.append(.wouldLeaveNoDisplay(name: info.name))
            return records
        }

        do {
            let flagged = DisplayRegistry.setDisconnectedByLumen(true, uuid: uuid, in: records)
            try backend.setEnabled(false, displayID: info.displayID)
            return flagged
        } catch {
            report.failures.append(.backend(info.name, error))
            return records
        }
    }

    private func change(_ uuid: String, records: [DisplayRecord], report: inout RunReport, _ body: (DisplayInfo) throws -> Void) {
        guard let info = onlineInfo(uuid) else {
            report.failures.append(DisplayFailure(name: name(of: uuid, in: records), reason: .notOnline))
            return
        }
        do {
            try body(info)
        } catch {
            report.failures.append(.backend(info.name, error))
        }
    }

    /// Polls until every display is online, returning the ones that never appeared.
    private func waitForOnline(_ uuids: [String]) async -> [String] {
        guard !uuids.isEmpty else { return [] }
        let clock = ContinuousClock()
        let deadline = clock.now + onlineTimeout
        while true {
            let online = Set(backend.onlineDisplays().filter(\.isActive).map(\.uuid))
            let missing = uuids.filter { !online.contains($0) }
            if missing.isEmpty || clock.now >= deadline { return missing }
            try? await Task.sleep(for: pollInterval)
        }
    }

    private func onlineInfo(_ uuid: String) -> DisplayInfo? {
        backend.onlineDisplays().first { $0.uuid == uuid && $0.isActive }
    }

    private func name(of uuid: String, in records: [DisplayRecord]) -> String {
        records.first { $0.id == uuid }?.info.name ?? "A display"
    }

    private func finish(_ records: [DisplayRecord], _ report: RunReport) -> WorkerResult {
        WorkerResult(records: DisplayRegistry.merge(records: records, online: backend.onlineDisplays()), report: report)
    }
}
