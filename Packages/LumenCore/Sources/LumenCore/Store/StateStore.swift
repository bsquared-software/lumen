import Foundation

/// Reads and writes `LumenState` as pretty-printed JSON.
public struct StateStore: Sendable {
    public let fileURL: URL

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// `~/Library/Application Support/Lumen/state.json`
    public static func applicationSupport() -> StateStore {
        StateStore(fileURL: URL.applicationSupportDirectory.appending(path: "Lumen/state.json"))
    }

    /// `nil` when nothing has been saved yet. Throws when the file exists but cannot be read,
    /// so a corrupt file is reported rather than silently replaced with defaults.
    public func load() throws -> LumenState? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        return try JSONDecoder().decode(LumenState.self, from: Data(contentsOf: fileURL))
    }

    public func save(_ state: LumenState) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(state).write(to: fileURL, options: .atomic)
    }
}
