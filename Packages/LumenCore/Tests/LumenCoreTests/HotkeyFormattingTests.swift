import Testing
@testable import LumenCore

@Suite struct HotkeyFormattingTests {
    @Test func modifierSymbolsFollowTheMacOrder() {
        let all = HotkeyModifiers.command | HotkeyModifiers.shift | HotkeyModifiers.option | HotkeyModifiers.control
        #expect(HotkeyFormatting.modifierSymbols(all) == "⌃⌥⇧⌘")
        #expect(HotkeyFormatting.modifierSymbols(HotkeyModifiers.command) == "⌘")
    }

    @Test func displayStringJoinsModifiersAndKey() {
        let hotkey = Hotkey(keyCode: 45, modifiers: HotkeyModifiers.control | HotkeyModifiers.option | HotkeyModifiers.command, keyLabel: "N")
        #expect(hotkey.displayString == "⌃⌥⌘N")
    }

    @Test func convertsCocoaModifierFlagsToCarbon() {
        let cocoaCommandOption: UInt = (1 << 20) | (1 << 19)
        #expect(HotkeyFormatting.carbonModifiers(fromCocoa: cocoaCommandOption) == HotkeyModifiers.command | HotkeyModifiers.option)
        let cocoaControlShift: UInt = (1 << 18) | (1 << 17)
        #expect(HotkeyFormatting.carbonModifiers(fromCocoa: cocoaControlShift) == HotkeyModifiers.control | HotkeyModifiers.shift)
    }

    @Test func aShortcutNeedsControlOrOptionOrCommandWithShift() {
        #expect(HotkeyFormatting.isAcceptable(modifiers: HotkeyModifiers.control))
        #expect(HotkeyFormatting.isAcceptable(modifiers: HotkeyModifiers.option | HotkeyModifiers.command))
        #expect(HotkeyFormatting.isAcceptable(modifiers: HotkeyModifiers.command | HotkeyModifiers.shift))
        // ⌘ alone would take over shortcuts like ⌘C in every app.
        #expect(!HotkeyFormatting.isAcceptable(modifiers: HotkeyModifiers.command))
        #expect(!HotkeyFormatting.isAcceptable(modifiers: HotkeyModifiers.shift))
        #expect(!HotkeyFormatting.isAcceptable(modifiers: 0))
    }

    @Test func namesSpecialKeysAndUppercasesCharacters() {
        #expect(HotkeyFormatting.keyLabel(keyCode: 122, characters: nil) == "F1")
        #expect(HotkeyFormatting.keyLabel(keyCode: 49, characters: " ") == "Space")
        #expect(HotkeyFormatting.keyLabel(keyCode: 126, characters: nil) == "↑")
        #expect(HotkeyFormatting.keyLabel(keyCode: 45, characters: "n") == "N")
        #expect(HotkeyFormatting.keyLabel(keyCode: 200, characters: nil) == "Key 200")
    }

    @Test func spokenDescriptionNamesModifiersInWords() {
        let hotkey = Hotkey(keyCode: 45, modifiers: HotkeyModifiers.control | HotkeyModifiers.option | HotkeyModifiers.command, keyLabel: "N")
        #expect(hotkey.spokenDescription == "Control Option Command N")
        #expect(Hotkey(keyCode: 49, modifiers: HotkeyModifiers.shift | HotkeyModifiers.command, keyLabel: "Space").spokenDescription == "Shift Command Space")
    }
}
