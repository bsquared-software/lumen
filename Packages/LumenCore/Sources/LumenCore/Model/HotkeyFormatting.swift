import Foundation

/// Turns shortcut data into what macOS users expect to read, and recorded key events into
/// `Hotkey` values. AppKit-free so it can be tested here.
public enum HotkeyFormatting {
    /// `⌃⌥⇧⌘`, the order macOS menus use.
    public static func modifierSymbols(_ modifiers: UInt32) -> String {
        [
            (HotkeyModifiers.control, "⌃"), (HotkeyModifiers.option, "⌥"),
            (HotkeyModifiers.shift, "⇧"), (HotkeyModifiers.command, "⌘"),
        ]
        .filter { modifiers & $0.0 != 0 }
        .map(\.1)
        .joined()
    }

    /// `NSEvent.ModifierFlags.rawValue` to Carbon modifier masks.
    public static func carbonModifiers(fromCocoa flags: UInt) -> UInt32 {
        let mapping: [(cocoa: UInt, carbon: UInt32)] = [
            (1 << 17, HotkeyModifiers.shift), (1 << 18, HotkeyModifiers.control),
            (1 << 19, HotkeyModifiers.option), (1 << 20, HotkeyModifiers.command),
        ]
        return mapping.filter { flags & $0.cocoa != 0 }.reduce(0) { $0 | $1.carbon }
    }

    /// A global shortcut needs ⌃ or ⌥, or ⌘ with ⇧. Shift alone fires while typing, and ⌘ alone
    /// would take over app shortcuts such as ⌘C everywhere.
    public static func isAcceptable(modifiers: UInt32) -> Bool {
        if modifiers & (HotkeyModifiers.control | HotkeyModifiers.option) != 0 { return true }
        let commandShift = HotkeyModifiers.command | HotkeyModifiers.shift
        return modifiers & commandShift == commandShift
    }

    public static func keyLabel(keyCode: UInt32, characters: String?) -> String {
        if let special = specialKeys[keyCode] { return special }
        if let characters, !characters.trimmingCharacters(in: .whitespaces).isEmpty {
            return characters.uppercased()
        }
        return "Key \(keyCode)"
    }

    private static let specialKeys: [UInt32: String] = [
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
        49: "Space", 36: "↩", 48: "⇥", 51: "⌫", 53: "⎋", 117: "⌦",
        123: "←", 124: "→", 125: "↓", 126: "↑", 115: "↖", 119: "↘", 116: "⇞", 121: "⇟",
    ]
}

extension Hotkey {
    public var displayString: String {
        HotkeyFormatting.modifierSymbols(modifiers) + keyLabel
    }
}
