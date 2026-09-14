import Foundation

/// Carbon modifier masks (`cmdKey`, `shiftKey`, `optionKey`, `controlKey`), mirrored here so
/// LumenCore does not import Carbon.
public enum HotkeyModifiers {
    public static let command: UInt32 = 0x0100
    public static let shift: UInt32 = 0x0200
    public static let option: UInt32 = 0x0800
    public static let control: UInt32 = 0x1000
}

/// A global keyboard shortcut. `keyCode` is a virtual key code (`kVK_ANSI_N` is 45).
public struct Hotkey: Codable, Hashable, Sendable {
    public var keyCode: UInt32
    public var modifiers: UInt32
    /// What the key prints as, captured when the shortcut was recorded ("N", "F5", "Space").
    public var keyLabel: String

    public init(keyCode: UInt32, modifiers: UInt32, keyLabel: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.keyLabel = keyLabel
    }
}

/// What a preset wants for one display. `nil` brightness or mode means "leave as it is".
public struct DisplayTarget: Codable, Hashable, Sendable, Identifiable {
    public var id: String { uuid }

    public var uuid: String
    /// The display's name when the preset was saved, for messages when it is not attached.
    public var name: String
    public var connected: Bool
    public var brightness: Double?
    public var mode: DisplayMode?

    public init(uuid: String, name: String, connected: Bool, brightness: Double? = nil, mode: DisplayMode? = nil) {
        self.uuid = uuid
        self.name = name
        self.connected = connected
        self.brightness = brightness
        self.mode = mode
    }
}

public struct Preset: Codable, Hashable, Sendable, Identifiable {
    public var id: UUID
    public var name: String
    /// SF Symbol shown on the preset button and in the menu bar while it is active.
    public var symbol: String
    public var hotkey: Hotkey?
    public var displays: [DisplayTarget]

    public init(id: UUID = UUID(), name: String, symbol: String, hotkey: Hotkey? = nil, displays: [DisplayTarget]) {
        self.id = id
        self.name = name
        self.symbol = symbol
        self.hotkey = hotkey
        self.displays = displays
    }
}
