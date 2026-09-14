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

    static func worker(_ backend: FakeBackend) -> DisplayWorker {
        DisplayWorker(backend: backend, onlineTimeout: .milliseconds(200), pollInterval: .milliseconds(5))
    }

    @Test func applyingNightDimsTheBuiltinThenDisconnectsAndRemembersExternals() async {
        let backend = FakeBackend(displays: Self.desk)
        let result = await Self.worker(backend).apply(Desk.night, records: Self.allRecords)

        #expect(backend.calls == [.setBrightness(0.10, 1), .setEnabled(false, 2), .setEnabled(false, 3)])
        #expect(result.records.filter(\.disconnectedByLumen).map(\.id) == ["G81", "LS32"])
        #expect(result.report.isClean)
    }

    @Test func applyingDayReconnectsByRememberedIDAndWaitsBeforeSettingValues() async {
        let backend = FakeBackend(displays: Self.desk, enabled: [1])
        backend.configure { $0.pollsUntilOnline = 3 }
        let result = await Self.worker(backend).apply(Desk.day, records: Self.nightRecords)

        #expect(backend.calls == [
            .setEnabled(true, 2), .setEnabled(true, 3), .setMode(Desk.hiDPI1440, 2), .setBrightness(0.6, 1),
        ])
        #expect(result.records.allSatisfy { !$0.disconnectedByLumen })
        #expect(result.report.isClean)
    }

    @Test func aDisplayThatNeverComesBackIsReportedOnce() async {
        let backend = FakeBackend(displays: Self.desk, enabled: [1])
        backend.configure { $0.neverComesBack = [2] }
        let result = await Self.worker(backend).apply(Desk.day, records: Self.nightRecords)

        #expect(result.report.failures == [DisplayFailure(name: "Odyssey G81SF", reason: .didNotComeBack)])
        #expect(!backend.calls.contains(.setMode(Desk.hiDPI1440, 2)))
        #expect(result.records.first { $0.id == "G81" }?.disconnectedByLumen == true)
    }

    @Test func refusesToDisconnectTheLastDisplay() async {
        let backend = FakeBackend(displays: Self.desk, enabled: [1])
        let result = await Self.worker(backend).setConnected(false, uuid: "BUILTIN", records: Self.nightRecords)

        #expect(backend.calls.isEmpty)
        #expect(result.report.skipped == [.wouldLeaveNoDisplay(name: "Built-in Display")])
    }

    @Test func aFailedDisconnectLeavesTheDisplayUnflagged() async {
        let backend = FakeBackend(displays: Self.desk)
        backend.configure { $0.failingDisable = [3] }
        let result = await Self.worker(backend).setConnected(false, uuid: "LS32", records: Self.allRecords)

        #expect(result.records.first { $0.id == "LS32" }?.disconnectedByLumen == false)
        #expect(result.report.failures.map(\.name) == ["LS32D70xE"])
    }

    @Test func switchingADisplayBackOnWaitsForIt() async {
        let backend = FakeBackend(displays: Self.desk, enabled: [1, 2])
        backend.configure { $0.pollsUntilOnline = 2 }
        let records = [Self.allRecords[0], Self.allRecords[1], DisplayRecord(info: Desk.ls32, disconnectedByLumen: true)]
        let result = await Self.worker(backend).setConnected(true, uuid: "LS32", records: records)

        #expect(backend.calls == [.setEnabled(true, 3)])
        #expect(result.report.isClean)
        #expect(result.records.allSatisfy { !$0.disconnectedByLumen })
    }

    @Test func reconnectAllTurnsOnEveryRememberedDisplay() async {
        let backend = FakeBackend(displays: Self.desk, enabled: [1])
        let result = await Self.worker(backend).reconnectAll(records: Self.nightRecords)

        #expect(backend.calls == [.setEnabled(true, 2), .setEnabled(true, 3)])
        #expect(result.report.isClean)
    }

    @Test func snapshotListsDisconnectedDisplaysAndToleratesUnreadableBrightness() async {
        let backend = FakeBackend(displays: Self.desk, enabled: [1, 2])
        backend.configure { $0.noBrightness = [2] }
        let records = [Self.allRecords[0], Self.allRecords[1], DisplayRecord(info: Desk.ls32, disconnectedByLumen: true)]
        let snapshot = await Self.worker(backend).snapshot(records: records)

        #expect(snapshot.displays.map(\.known.status) == [.online, .online, .disconnected])
        #expect(snapshot.displays.map(\.brightness) == [0.5, nil, nil])
        #expect(snapshot.displays[0].currentMode == Desk.hiDPI1440)
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
