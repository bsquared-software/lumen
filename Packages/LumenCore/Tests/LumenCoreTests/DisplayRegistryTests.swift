import Testing
@testable import LumenCore

@Suite struct DisplayRegistryTests {
    @Test func addsNewlySeenDisplays() {
        let records = DisplayRegistry.merge(records: [], online: [Desk.builtin, Desk.g81])
        #expect(records == [
            DisplayRecord(info: Desk.builtin, disconnectedByLumen: false),
            DisplayRecord(info: Desk.g81, disconnectedByLumen: false),
        ])
    }

    @Test func refreshesDetailsOfKnownDisplays() {
        var moved = Desk.g81
        moved.displayID = 7
        let records = DisplayRegistry.merge(records: [DisplayRecord(info: Desk.g81, disconnectedByLumen: false)], online: [moved])
        #expect(records.first?.info.displayID == 7)
    }

    @Test func clearsTheLumenFlagWhenADisplayIsOnlineAgain() {
        let records = DisplayRegistry.merge(records: [DisplayRecord(info: Desk.g81, disconnectedByLumen: true)], online: [Desk.g81])
        #expect(records.first?.disconnectedByLumen == false)
    }

    @Test func keepsTheLumenFlagForDisplaysStillBeingSwitchedOff() {
        let records = DisplayRegistry.merge(
            records: [DisplayRecord(info: Desk.g81, disconnectedByLumen: true)], online: [Desk.g81], keepingFlagsFor: ["G81"]
        )
        #expect(records.first?.disconnectedByLumen == true)
    }

    @Test func keepsOfflineRecords() {
        let saved = [DisplayRecord(info: Desk.ls32, disconnectedByLumen: true), DisplayRecord(info: Desk.g81, disconnectedByLumen: false)]
        #expect(DisplayRegistry.merge(records: saved, online: [Desk.builtin]).count == 3)
    }

    @Test func knownDisplaysFollowTheDeskFromLeftToRight() {
        let records = [
            DisplayRecord(info: Desk.builtin, disconnectedByLumen: false),
            DisplayRecord(info: Desk.ls32, disconnectedByLumen: true),
            DisplayRecord(info: Desk.g81, disconnectedByLumen: false),
        ]
        let known = DisplayRegistry.knownDisplays(records: records, online: [Desk.builtin, Desk.g81], framebuffers: Desk.pluggedIn)
        // LS32 is switched off, so its remembered position keeps it on the right.
        #expect(known.map(\.id) == ["G81", "BUILTIN", "LS32"])
        #expect(known.map(\.status) == [.online, .online, .disconnected])
    }

    @Test func displaysWithoutAKnownPositionComeLastInRecordOrder() {
        let unplaced = DisplayInfo.fixture(uuid: "TV", name: "TV", displayID: 9, vendor: 7, model: 7, serial: 7)
        let other = DisplayInfo.fixture(uuid: "PROJECTOR", name: "Projector", displayID: 8, vendor: 6, model: 6, serial: 6)
        let records = [unplaced, Desk.ls32, other, Desk.builtin].map { DisplayRecord(info: $0, disconnectedByLumen: false) }
        let known = DisplayRegistry.knownDisplays(records: records, online: [unplaced, Desk.ls32, other, Desk.builtin], framebuffers: [])
        #expect(known.map(\.id) == ["BUILTIN", "LS32", "TV", "PROJECTOR"])
    }

    @Test func knownDisplaysUseTheCustomNameWhenThereIsOne() {
        let records = [
            DisplayRecord(info: Desk.g81, disconnectedByLumen: false, customName: "Left OLED"),
            DisplayRecord(info: Desk.ls32, disconnectedByLumen: false),
        ]
        let known = DisplayRegistry.knownDisplays(records: records, online: [Desk.g81, Desk.ls32], framebuffers: Desk.pluggedIn)
        #expect(known.map(\.displayName) == ["Left OLED", "LS32D70xE"])
    }

    @Test func mergingKeepsCustomNames() {
        let records = DisplayRegistry.merge(records: [DisplayRecord(info: Desk.g81, disconnectedByLumen: false, customName: "Left OLED")], online: [Desk.g81])
        #expect(records.first?.customName == "Left OLED")
    }

    @Test func aSwitchedOffMonitorWithNoFramebufferIsUnavailable() {
        let records = [DisplayRecord(info: Desk.builtin, disconnectedByLumen: false), DisplayRecord(info: Desk.ls32, disconnectedByLumen: true)]
        let known = DisplayRegistry.knownDisplays(records: records, online: [Desk.builtin], framebuffers: [Desk.pluggedIn[0]])
        #expect(known.map(\.status) == [.online, .unavailable])
    }

    @Test func aSwitchedOffBuiltinCountsAsAttachedWhileItsPanelExists() {
        let records = [DisplayRecord(info: Desk.builtin, disconnectedByLumen: true), DisplayRecord(info: Desk.g81, disconnectedByLumen: false)]
        let known = DisplayRegistry.knownDisplays(records: records, online: [Desk.g81], framebuffers: Desk.pluggedIn)
        #expect(known.first { $0.id == "BUILTIN" }?.status == .disconnected)
    }

    @Test func settingTheLumenFlagTouchesOnlyThatDisplay() {
        let records = [DisplayRecord(info: Desk.g81, disconnectedByLumen: false), DisplayRecord(info: Desk.ls32, disconnectedByLumen: false)]
        let updated = DisplayRegistry.setDisconnectedByLumen(true, uuid: "LS32", in: records)
        #expect(updated.map(\.disconnectedByLumen) == [false, true])
    }
}
