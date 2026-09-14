import Testing
@testable import LumenCore

@Suite struct DisplayStatusTests {
    static let record = DisplayRecord(info: Desk.ls32, disconnectedByLumen: false)
    static let flagged = DisplayRecord(info: Desk.ls32, disconnectedByLumen: true)

    @Test func onlineIsOnlineWhateverTheFlag() {
        #expect(DisplayStatus.resolve(record: Self.flagged, online: Desk.ls32, isAttached: true) == .online)
    }

    @Test func switchedOffByLumenAndStillPluggedInIsDisconnected() {
        #expect(DisplayStatus.resolve(record: Self.flagged, online: nil, isAttached: true) == .disconnected)
    }

    // Night, then undock: the monitor must not stay listed as "Switched off".
    @Test func switchedOffByLumenThenUnpluggedIsUnavailable() {
        #expect(DisplayStatus.resolve(record: Self.flagged, online: nil, isAttached: false) == .unavailable)
    }

    @Test func missingForAnyOtherReasonIsUnavailable() {
        #expect(DisplayStatus.resolve(record: Self.record, online: nil, isAttached: true) == .unavailable)
    }
}
