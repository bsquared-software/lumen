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

    @Test func updatingFromCurrentSetupKeepsMonitorsThatAreUnpluggedNow() {
        let captured = [
            CapturedDisplay(display: Desk.known(Desk.builtin, .online), brightness: 0.3, mode: nil),
            CapturedDisplay(display: Desk.known(Desk.g81, .unavailable), brightness: nil, mode: nil),
        ]
        let updated = PresetFactory.updating(Desk.day, from: captured)
        #expect(updated.name == "Day")
        #expect(updated.displays == [
            DisplayTarget(uuid: "G81", name: "Odyssey G81SF", connected: true, mode: Desk.hiDPI1440),
            DisplayTarget(uuid: "LS32", name: "LS32D70xE", connected: true),
            DisplayTarget(uuid: "BUILTIN", name: "Built-in Display", connected: true, brightness: 0.3),
        ])
    }

    @Test func updatingFromCurrentSetupAddsNewlyAttachedDisplays() {
        let preset = Preset(name: "Laptop", symbol: "laptopcomputer", displays: [
            DisplayTarget(uuid: "BUILTIN", name: "Built-in Display", connected: true),
        ])
        let captured = [
            CapturedDisplay(display: Desk.known(Desk.builtin, .online), brightness: nil, mode: nil),
            CapturedDisplay(display: Desk.known(Desk.ls32, .disconnected), brightness: nil, mode: nil),
        ]
        #expect(PresetFactory.updating(preset, from: captured).displays.map(\.uuid) == ["BUILTIN", "LS32"])
    }

    @Test func uniqueNamesCountUpFromTwo() {
        #expect(PresetFactory.uniqueName("New Preset", existing: ["Night", "Day"]) == "New Preset")
        #expect(PresetFactory.uniqueName("New Preset", existing: ["New Preset"]) == "New Preset 2")
        #expect(PresetFactory.uniqueName("New Preset", existing: ["New Preset", "New Preset 2"]) == "New Preset 3")
    }

    @Test func findsAttachedDisplaysMissingFromAPreset() {
        let laptopOnly = Preset(name: "Laptop", symbol: "laptopcomputer", displays: [
            DisplayTarget(uuid: "BUILTIN", name: "Built-in Display", connected: true),
        ])
        let displays = [Desk.known(Desk.g81, .online), Desk.known(Desk.builtin, .online), Desk.known(Desk.ls32, .unavailable)]
        #expect(PresetFactory.missingDisplays(in: laptopOnly, from: displays).map(\.id) == ["G81"])
    }

    @Test func addingADisplayLeavesItOnWithNoChanges() {
        let withoutG81 = PresetFactory.removing("G81", from: Desk.night)
        let added = PresetFactory.adding(Desk.known(Desk.g81, .online), to: withoutG81)
        #expect(added.displays.last == DisplayTarget(uuid: "G81", name: "Odyssey G81SF", connected: true))
        #expect(PresetFactory.adding(Desk.known(Desk.g81, .online), to: added).displays.count == added.displays.count)
    }

    @Test func addingUsesTheCustomName() {
        let named = KnownDisplay(info: Desk.g81, status: .online, customName: "Left OLED")
        let preset = Preset(name: "Empty", symbol: "display", displays: [])
        #expect(PresetFactory.adding(named, to: preset).displays.first?.name == "Left OLED")
    }

    @Test func removingADisplayDropsOnlyThatTarget() {
        #expect(PresetFactory.removing("LS32", from: Desk.night).displays.map(\.uuid) == ["G81", "BUILTIN"])
    }

    @Test func duplicatingCopiesDisplaysButNotTheShortcut() {
        var night = Desk.night
        night.hotkey = Hotkey(keyCode: 45, modifiers: HotkeyModifiers.control | HotkeyModifiers.option, keyLabel: "N")
        let copy = PresetFactory.duplicate(night, existingNames: ["Night", "Day", "Night Copy"])

        #expect(copy.id != night.id)
        #expect(copy.name == "Night Copy 2")
        #expect(copy.symbol == night.symbol)
        #expect(copy.hotkey == nil)
        #expect(copy.displays == night.displays)
    }

    @Test func targetsFollowTheDeskOrder() {
        var night = Desk.night
        night.displays.append(DisplayTarget(uuid: "GONE", name: "Old TV", connected: false))
        let desk = [Desk.known(Desk.g81, .online), Desk.known(Desk.builtin, .online), Desk.known(Desk.ls32, .online)]
        #expect(PresetFactory.deskOrder(of: night.displays, displays: desk) == ["G81", "BUILTIN", "LS32", "GONE"])
    }

    @Test func namesMustBePresentForLinksToWork() {
        #expect(PresetFactory.nameProblem("  ", for: Desk.night.id, in: [Desk.night, Desk.day]) == "Give this preset a name so its link works.")
    }

    @Test func duplicateNamesAreFlagged() {
        #expect(PresetFactory.nameProblem("day", for: Desk.night.id, in: [Desk.night, Desk.day])
            == "Another preset is called “Day”, so a link to this name applies whichever comes first.")
        #expect(PresetFactory.nameProblem("Night", for: Desk.night.id, in: [Desk.night, Desk.day]) == nil)
    }
}
