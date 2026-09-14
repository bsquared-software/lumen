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

    @Test func clearsTheLumenFlagWhenADisplayIsActiveAgain() {
        let records = DisplayRegistry.merge(records: [DisplayRecord(info: Desk.g81, disconnectedByLumen: true)], online: [Desk.g81])
        #expect(records.first?.disconnectedByLumen == false)
    }

    @Test func keepsTheLumenFlagWhileADisplayIsOnlineButInactive() {
        var inactive = Desk.g81
        inactive.isActive = false
        let records = DisplayRegistry.merge(records: [DisplayRecord(info: Desk.g81, disconnectedByLumen: true)], online: [inactive])
        #expect(records.first?.disconnectedByLumen == true)
    }

    @Test func keepsOfflineRecords() {
        let saved = [DisplayRecord(info: Desk.ls32, disconnectedByLumen: true), DisplayRecord(info: Desk.g81, disconnectedByLumen: false)]
        #expect(DisplayRegistry.merge(records: saved, online: [Desk.builtin]).count == 3)
    }

    @Test func knownDisplaysResolveStatusAndPutTheBuiltinFirst() {
        let records = [
            DisplayRecord(info: Desk.g81, disconnectedByLumen: false),
            DisplayRecord(info: Desk.ls32, disconnectedByLumen: true),
            DisplayRecord(info: Desk.builtin, disconnectedByLumen: false),
        ]
        let known = DisplayRegistry.knownDisplays(records: records, online: [Desk.builtin, Desk.g81])
        #expect(known.map(\.id) == ["BUILTIN", "G81", "LS32"])
        #expect(known.map(\.status) == [.online, .online, .disconnected])
    }

    @Test func settingTheLumenFlagTouchesOnlyThatDisplay() {
        let records = [DisplayRecord(info: Desk.g81, disconnectedByLumen: false), DisplayRecord(info: Desk.ls32, disconnectedByLumen: false)]
        let updated = DisplayRegistry.setDisconnectedByLumen(true, uuid: "LS32", in: records)
        #expect(updated.map(\.disconnectedByLumen) == [false, true])
    }
}
