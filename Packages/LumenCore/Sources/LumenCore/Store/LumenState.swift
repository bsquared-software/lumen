import Foundation

/// Everything Lumen persists, in one JSON file. New fields are optional so older files load.
public struct LumenState: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var displays: [DisplayRecord]
    public var presets: [Preset]
    /// The preset applied most recently, so the menu bar icon survives a relaunch.
    public var activePresetID: UUID?
    /// Whether Lumen has already offered to open at login, so it asks only once.
    public var hasOfferedLoginItem: Bool?

    public init(displays: [DisplayRecord], presets: [Preset], activePresetID: UUID? = nil, hasOfferedLoginItem: Bool? = nil) {
        self.schemaVersion = Self.currentSchemaVersion
        self.displays = displays
        self.presets = presets
        self.activePresetID = activePresetID
        self.hasOfferedLoginItem = hasOfferedLoginItem
    }
}
