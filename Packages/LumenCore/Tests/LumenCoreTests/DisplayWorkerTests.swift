import Testing
@testable import LumenCore

@Suite struct DisplayWorkerTests {
    static let desk = [Desk.builtin, Desk.g81, Desk.ls32]
    static let allRecords = desk.map { DisplayRecord(info: $0, disconnectedByLumen: false) }
    static let nightRecords = [
        DisplayRecord(info: Desk.builtin, disconnectedByLumen: false),
        DisplayRecord(info: Desk.g81, disconnectedByLumen: true),
        DisplayRecord(info: Desk.ls32, disconnectedByLumen: true),
    ]

    static func worker(_ backend: FakeBackend, records: [DisplayRecord]) -> DisplayWorker {
        DisplayWorker(backend: backend, records: records, onlineTimeout: .milliseconds(200), pollInterval: .milliseconds(5))
    }

    static func flagged(_ worker: DisplayWorker) async -> [String] {
        await worker.snapshot().records.filter(\.disconnectedByLumen).map(\.id)
    }

    @Test func applyingNightDimsTheBuiltinThenDisconnectsAndRemembersExternals() async {
        let backend = FakeBackend(displays: Self.desk)
        let worker = Self.worker(backend, records: Self.allRecords)
        let report = await worker.apply(Desk.night)

        #expect(backend.calls == [.setBrightness(0.10, 1), .setEnabled(false, 2), .setEnabled(false, 3)])
        #expect(await Self.flagged(worker) == ["G81", "LS32"])
        #expect(report.isClean)
    }

    @Test func applyingDayReconnectsByRememberedIDAndWaitsBeforeSettingValues() async {
        let backend = FakeBackend(displays: Self.desk, enabled: [1])
        backend.configure { $0.pollsUntilOnline = 3 }
        let worker = Self.worker(backend, records: Self.nightRecords)
        let report = await worker.apply(Desk.day)

        #expect(backend.calls == [
            .setEnabled(true, 2), .setEnabled(true, 3), .setMode(Desk.hiDPI1440, 2), .setBrightness(0.6, 1),
        ])
        #expect(await Self.flagged(worker).isEmpty)
        #expect(report.isClean)
    }

    @Test func aDisplayThatNeverComesBackIsReportedOnce() async {
        let backend = FakeBackend(displays: Self.desk, enabled: [1])
        backend.configure { $0.neverComesBack = [2] }
        let worker = Self.worker(backend, records: Self.nightRecords)
        let report = await worker.apply(Desk.day)

        #expect(report.failures == [DisplayFailure(name: "Odyssey G81SF", reason: .didNotComeBack)])
        #expect(!backend.calls.contains(.setMode(Desk.hiDPI1440, 2)))
        #expect(await Self.flagged(worker) == ["G81"])
    }

    // Clamshell swap: G81 off, LS32 on. If LS32 fails to return, G81 must stay on.
    @Test func aFailedReconnectNeverLeavesTheMacWithoutADisplay() async {
        let swap = Preset(name: "Swap", symbol: "display", displays: [
            DisplayTarget(uuid: "LS32", name: "LS32D70xE", connected: true),
            DisplayTarget(uuid: "G81", name: "Odyssey G81SF", connected: false),
        ])
        let clamshell = [Desk.g81, Desk.ls32]
        let records = [DisplayRecord(info: Desk.g81, disconnectedByLumen: false), DisplayRecord(info: Desk.ls32, disconnectedByLumen: true)]

        for failure in ["never comes back", "enable throws"] {
            let backend = FakeBackend(displays: clamshell, enabled: [2])
            backend.configure { failure == "enable throws" ? ($0.failingEnable = [3]) : ($0.neverComesBack = [3]) }
            let report = await Self.worker(backend, records: records).apply(swap)

            #expect(!backend.calls.contains(.setEnabled(false, 2)), "\(failure)")
            #expect(report.skipped.contains(.wouldLeaveNoDisplay(name: "Odyssey G81SF")), "\(failure)")
        }
    }

    @Test func aDisplayThatLingersAfterDisconnectStillCountsAsOff() async {
        let backend = FakeBackend(displays: [Desk.g81, Desk.ls32])
        backend.configure { $0.pollsUntilOffline = 3 }
        let records = [DisplayRecord(info: Desk.g81, disconnectedByLumen: false), DisplayRecord(info: Desk.ls32, disconnectedByLumen: false)]
        let worker = Self.worker(backend, records: records)

        _ = await worker.setConnected(false, uuid: "G81")
        let report = await worker.setConnected(false, uuid: "LS32")

        #expect(backend.calls == [.setEnabled(false, 2)])
        #expect(report.skipped == [.wouldLeaveNoDisplay(name: "LS32D70xE")])
        #expect(await Self.flagged(worker) == ["G81"])
    }

    @Test func overlappingSwitchOffsKeepTheDisplayRemembered() async {
        let backend = FakeBackend(displays: Self.desk)
        let worker = Self.worker(backend, records: Self.allRecords)

        async let first = worker.setConnected(false, uuid: "LS32")
        async let second = worker.setConnected(false, uuid: "LS32")
        _ = await (first, second)

        #expect(await Self.flagged(worker) == ["LS32"])
        #expect(await worker.snapshot().displays.first { $0.id == "LS32" }?.known.status == .disconnected)
    }

    @Test func refusesToDisconnectTheLastDisplay() async {
        let backend = FakeBackend(displays: Self.desk, enabled: [1])
        let report = await Self.worker(backend, records: Self.nightRecords).setConnected(false, uuid: "BUILTIN")

        #expect(backend.calls.isEmpty)
        #expect(report.skipped == [.wouldLeaveNoDisplay(name: "Built-in Display")])
    }

    @Test func aFailedDisconnectLeavesTheDisplayUnflagged() async {
        let backend = FakeBackend(displays: Self.desk)
        backend.configure { $0.failingDisable = [3] }
        let worker = Self.worker(backend, records: Self.allRecords)
        let report = await worker.setConnected(false, uuid: "LS32")

        #expect(await Self.flagged(worker).isEmpty)
        #expect(report.failures.map(\.name) == ["LS32D70xE"])
    }

    @Test func switchingADisplayBackOnWaitsForIt() async {
        let backend = FakeBackend(displays: Self.desk, enabled: [1, 2])
        backend.configure { $0.pollsUntilOnline = 2 }
        let records = [Self.allRecords[0], Self.allRecords[1], DisplayRecord(info: Desk.ls32, disconnectedByLumen: true)]
        let worker = Self.worker(backend, records: records)
        let report = await worker.setConnected(true, uuid: "LS32")

        #expect(backend.calls == [.setEnabled(true, 3)])
        #expect(report.isClean)
        #expect(await Self.flagged(worker).isEmpty)
    }

    @Test func reconnectAllTurnsOnEveryRememberedDisplay() async {
        let backend = FakeBackend(displays: Self.desk, enabled: [1])
        let report = await Self.worker(backend, records: Self.nightRecords).reconnectAll()

        #expect(backend.calls == [.setEnabled(true, 2), .setEnabled(true, 3)])
        #expect(report.isClean)
    }

    @Test func reconnectAllSkipsMonitorsThatWereUnplugged() async {
        let backend = FakeBackend(displays: Self.desk, enabled: [1])
        backend.configure { $0.pluggedIn = [1, 3] }
        let report = await Self.worker(backend, records: Self.nightRecords).reconnectAll()

        #expect(backend.calls == [.setEnabled(true, 3)])
        #expect(report.isClean)
    }

    @Test func snapshotListsDisconnectedDisplaysAndToleratesUnreadableBrightness() async {
        let backend = FakeBackend(displays: Self.desk, enabled: [1, 2])
        backend.configure { $0.noBrightness = [2] }
        let records = [Self.allRecords[0], Self.allRecords[1], DisplayRecord(info: Desk.ls32, disconnectedByLumen: true)]
        let snapshot = await Self.worker(backend, records: records).snapshot()

        #expect(snapshot.displays.map(\.known.status) == [.online, .online, .disconnected])
        #expect(snapshot.displays.map(\.brightness) == [0.5, nil, nil])
        #expect(snapshot.displays[0].currentMode == Desk.hiDPI1440)
        #expect(snapshot.displays[0].options.map(\.id) == ["2560x1440@2x"])
    }

    @Test func brightnessFailuresReachTheCaller() async {
        let backend = FakeBackend(displays: Self.desk)
        backend.configure { $0.noBrightness = [3] }
        let worker = Self.worker(backend, records: Self.allRecords)
        await #expect(throws: DisplayError.brightnessUnsupported) { try await worker.setBrightness(0.4, uuid: "LS32") }
    }

    @Test func reportMessagesReadNaturally() {
        let report = RunReport(
            skipped: [.notAttached(name: "Old TV"), .wouldLeaveNoDisplay(name: "LS32D70xE")],
            failures: [DisplayFailure(name: "Odyssey G81SF", reason: .didNotComeBack)]
        )
        #expect(report.messages == [
            "Old TV isn’t plugged in, so it was skipped.",
            "LS32D70xE stayed on so you’re not left without a screen.",
            "Odyssey G81SF didn’t come back. Try unplugging it and plugging it in again.",
        ])
    }
}
