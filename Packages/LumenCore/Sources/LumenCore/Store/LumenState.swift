/// Everything Lumen persists, in one JSON file.
public struct LumenState: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var displays: [DisplayRecord]
    public var presets: [Preset]

    public init(displays: [DisplayRecord], presets: [Preset]) {
        self.schemaVersion = Self.currentSchemaVersion
        self.displays = displays
        self.presets = presets
    }
}
