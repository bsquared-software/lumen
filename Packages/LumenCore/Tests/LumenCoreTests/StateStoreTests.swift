import Foundation
import Testing
@testable import LumenCore

@Suite struct StateStoreTests {
    let directory = FileManager.default.temporaryDirectory.appending(path: "lumen-tests-\(UUID().uuidString)")
    var store: StateStore { StateStore(fileURL: directory.appending(path: "Lumen/state.json")) }

    @Test func missingFileLoadsAsNil() throws {
        #expect(try store.load() == nil)
    }

    @Test func roundTripsDisplaysAndPresets() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let state = LumenState(
            displays: [DisplayRecord(info: Desk.ls32, disconnectedByLumen: true)],
            presets: [Desk.night, Desk.day]
        )
        try store.save(state)
        #expect(try store.load() == state)
    }

    @Test func writesTheCurrentSchemaVersion() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        try store.save(LumenState(displays: [], presets: []))
        let json = try String(contentsOf: store.fileURL, encoding: .utf8)
        #expect(json.contains("\"schemaVersion\" : 1"))
    }

    @Test func corruptFileThrows() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: store.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: store.fileURL)
        #expect(throws: (any Error).self) { try store.load() }
    }

    @Test func quarantiningMovesACorruptFileAsideSoLoadingStartsFresh() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: store.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: store.fileURL)

        let moved = try store.quarantineCorruptFile()

        #expect(try store.load() == nil)
        #expect(moved.lastPathComponent.hasPrefix("state-unreadable-"))
        #expect(try String(contentsOf: moved, encoding: .utf8) == "not json")
    }
}
