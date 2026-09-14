import Testing
@testable import LumenCore

@Suite struct PresetFactoryTests {
    @Test func seedsNightWithExternalsOffAndBuiltinAtTenPercent() throws {
        let presets = PresetFactory.seedPresets(from: Desk.allOnline, builtinBrightness: 0.8)
        let night = try #require(presets.first { $0.name == "Night" })
        #expect(night.symbol == "moon.stars")
        #expect(night.hotkey == Hotkey(keyCode: 45, modifiers: HotkeyModifiers.control | HotkeyModifiers.option | HotkeyModifiers.command, keyLabel: "N"))
        #expect(night.displays == [
            DisplayTarget(uuid: "G81", name: "Odyssey G81SF", connected: false),
            DisplayTarget(uuid: "LS32", name: "LS32D70xE", connected: false),
            DisplayTarget(uuid: "BUILTIN", name: "Built-in Display", connected: true, brightness: 0.10),
        ])
    }

    @Test func seedsDayWithEverythingOnAndCurrentBuiltinBrightness() throws {
        let presets = PresetFactory.seedPresets(from: Desk.allOnline, builtinBrightness: 0.8)
        let day = try #require(presets.first { $0.name == "Day" })
        #expect(day.symbol == "sun.max")
        #expect(day.hotkey?.keyLabel == "D")
        #expect(day.displays == [
            DisplayTarget(uuid: "G81", name: "Odyssey G81SF", connected: true),
            DisplayTarget(uuid: "LS32", name: "LS32D70xE", connected: true),
            DisplayTarget(uuid: "BUILTIN", name: "Built-in Display", connected: true, brightness: 0.8),
        ])
    }

    @Test func seedingIgnoresUnavailableDisplays() {
        let displays = [Desk.known(Desk.g81, .online), Desk.known(Desk.ls32, .unavailable), Desk.known(Desk.builtin, .online)]
        let presets = PresetFactory.seedPresets(from: displays, builtinBrightness: nil)
        #expect(presets.allSatisfy { !$0.displays.contains { $0.uuid == "LS32" } })
    }

    @Test func captureRecordsStateOfEveryAttachedDisplay() {
        let captured = [
            CapturedDisplay(display: Desk.known(Desk.g81, .online), brightness: 0.4, mode: Desk.hiDPI1440),
            CapturedDisplay(display: Desk.known(Desk.ls32, .disconnected), brightness: nil, mode: nil),
            CapturedDisplay(display: Desk.known(Desk.builtin, .unavailable), brightness: nil, mode: nil),
        ]
        let preset = PresetFactory.capture(name: "Gaming", symbol: "gamecontroller", displays: captured)
        #expect(preset.name == "Gaming")
        #expect(preset.hotkey == nil)
        #expect(preset.displays == [
            DisplayTarget(uuid: "G81", name: "Odyssey G81SF", connected: true, brightness: 0.4, mode: Desk.hiDPI1440),
            DisplayTarget(uuid: "LS32", name: "LS32D70xE", connected: false),
        ])
    }
}
