import Testing
@testable import LumenCore

@Suite struct PresetPlannerTests {
    @Test func nightSetsBrightnessThenDisconnectsBothExternals() {
        let plan = PresetPlanner.plan(Desk.night, displays: Desk.allOnline)
        #expect(plan.steps == [
            .setBrightness(uuid: "BUILTIN", value: 0.10),
            .disconnect(uuid: "G81"),
            .disconnect(uuid: "LS32"),
        ])
        #expect(plan.skipped.isEmpty)
    }

    @Test func dayConnectsWaitsThenSetsModesThenBrightness() {
        let plan = PresetPlanner.plan(Desk.day, displays: Desk.nightState)
        #expect(plan.steps == [
            .connect(uuid: "G81"),
            .connect(uuid: "LS32"),
            .waitForOnline(uuids: ["G81", "LS32"]),
            .setMode(uuid: "G81", mode: Desk.hiDPI1440),
            .setBrightness(uuid: "BUILTIN", value: 0.6),
        ])
    }

    @Test func alreadyAppliedPresetOnlyReappliesValues() {
        let plan = PresetPlanner.plan(Desk.night, displays: Desk.nightState)
        #expect(plan.steps == [.setBrightness(uuid: "BUILTIN", value: 0.10)])
    }

    @Test func skipsDisplaysThatAreNotAttached() {
        let displays = [Desk.known(Desk.g81, .online), Desk.known(Desk.ls32, .unavailable), Desk.known(Desk.builtin, .online)]
        var preset = Desk.day
        preset.displays.append(DisplayTarget(uuid: "GONE", name: "Old TV", connected: true))
        let plan = PresetPlanner.plan(preset, displays: displays)
        #expect(plan.skipped == [.notAttached(name: "LS32D70xE"), .notAttached(name: "Old TV")])
        #expect(!plan.steps.contains(.connect(uuid: "LS32")))
    }

    @Test func neverDisconnectsTheBuiltinDisplay() {
        let preset = Preset(name: "Externals only", symbol: "display", displays: [
            DisplayTarget(uuid: "BUILTIN", name: "Built-in Display", connected: false),
        ])
        let plan = PresetPlanner.plan(preset, displays: Desk.allOnline)
        #expect(plan.steps.isEmpty)
        #expect(plan.skipped == [.builtinStaysOn(name: "Built-in Display")])
    }

    @Test func clamshellNightKeepsOneExternalOn() {
        let clamshell = [Desk.known(Desk.g81, .online), Desk.known(Desk.ls32, .online), Desk.known(Desk.builtin, .unavailable)]
        let plan = PresetPlanner.plan(Desk.night, displays: clamshell)
        #expect(plan.steps == [.disconnect(uuid: "G81")])
        #expect(plan.skipped == [.notAttached(name: "Built-in Display"), .wouldLeaveNoDisplay(name: "LS32D70xE")])
    }

    @Test func displaysOutsideThePresetCountAsStayingOn() {
        let lonely = Preset(name: "Laptop off", symbol: "display", displays: [
            DisplayTarget(uuid: "G81", name: "Odyssey G81SF", connected: false),
        ])
        let displays = [Desk.known(Desk.g81, .online), Desk.known(Desk.ls32, .online), Desk.known(Desk.builtin, .unavailable)]
        #expect(PresetPlanner.plan(lonely, displays: displays).steps == [.disconnect(uuid: "G81")])
    }

    @Test func clampsBrightnessIntoUnitRange() {
        let preset = Preset(name: "Blinding", symbol: "sun.max", displays: [
            DisplayTarget(uuid: "BUILTIN", name: "Built-in Display", connected: true, brightness: 1.7),
            DisplayTarget(uuid: "LS32", name: "LS32D70xE", connected: true, brightness: -1),
        ])
        #expect(PresetPlanner.plan(preset, displays: Desk.allOnline).steps == [
            .setBrightness(uuid: "BUILTIN", value: 1),
            .setBrightness(uuid: "LS32", value: 0),
        ])
    }

    @Test func ignoresValuesOnDisplaysBeingTurnedOff() {
        let preset = Preset(name: "Off", symbol: "moon", displays: [
            DisplayTarget(uuid: "LS32", name: "LS32D70xE", connected: false, brightness: 0.5, mode: Desk.hiDPI1440),
        ])
        #expect(PresetPlanner.plan(preset, displays: Desk.allOnline).steps == [.disconnect(uuid: "LS32")])
    }
}
