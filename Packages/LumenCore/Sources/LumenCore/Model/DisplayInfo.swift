import CoreGraphics

/// A display as CoreGraphics reports it right now.
///
/// `uuid` is the stable identity (it survives reboots and replugging). `displayID` is only
/// valid for the current session and must be refreshed after every reconfiguration.
public struct DisplayInfo: Codable, Hashable, Sendable, Identifiable {
    public var id: String { uuid }

    public let uuid: String
    public var displayID: CGDirectDisplayID
    public var name: String
    public var vendor: UInt32
    public var model: UInt32
    public var serial: UInt32
    public var isBuiltin: Bool

    public init(
        uuid: String, displayID: CGDirectDisplayID, name: String, vendor: UInt32, model: UInt32,
        serial: UInt32, isBuiltin: Bool
    ) {
        self.uuid = uuid
        self.displayID = displayID
        self.name = name
        self.vendor = vendor
        self.model = model
        self.serial = serial
        self.isBuiltin = isBuiltin
    }
}
