import Testing
@testable import LumenCore

@Suite struct DisplayStatusTests {
    static let record = DisplayRecord(info: Desk.ls32, disconnectedByLumen: false)

    @Test func onlineAndActiveIsOnline() {
        #expect(DisplayStatus.resolve(record: Self.record, online: Desk.ls32) == .online)
    }

    @Test func onlineButInactiveIsDisconnected() {
        var inactive = Desk.ls32
        inactive.isActive = false
        #expect(DisplayStatus.resolve(record: Self.record, online: inactive) == .disconnected)
    }

    @Test func missingButDisconnectedByLumenIsDisconnected() {
        let record = DisplayRecord(info: Desk.ls32, disconnectedByLumen: true)
        #expect(DisplayStatus.resolve(record: record, online: nil) == .disconnected)
    }

    @Test func missingForAnyOtherReasonIsUnavailable() {
        #expect(DisplayStatus.resolve(record: Self.record, online: nil) == .unavailable)
    }
}
