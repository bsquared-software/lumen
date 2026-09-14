import Foundation
import Testing
@testable import LumenCore

@Suite struct PresetLinkTests {
    static let nightMode = Preset(name: "Night Mode", symbol: "moon", displays: [])
    static let presets = [Desk.night, Desk.day, nightMode]

    static func resolve(_ link: String) -> Result<LinkAction, PresetLinkError> {
        PresetLink.action(for: URL(string: link)!, in: presets)
    }

    @Test func appliesAPresetByName() {
        #expect(Self.resolve("lumen://apply/Night") == .success(.apply(Desk.night)))
    }

    @Test func namesAreCaseInsensitive() {
        #expect(Self.resolve("lumen://apply/day") == .success(.apply(Desk.day)))
    }

    @Test func namesMayContainSpaces() {
        #expect(Self.resolve("lumen://apply/Night%20Mode") == .success(.apply(Self.nightMode)))
    }

    @Test func appliesAPresetByID() {
        #expect(Self.resolve("lumen://apply/\(Desk.day.id.uuidString)") == .success(.apply(Desk.day)))
    }

    @Test func reportsAnUnknownPreset() {
        #expect(Self.resolve("lumen://apply/Gaming") == .failure(.noPreset("Gaming")))
    }

    @Test func reportsAnUnknownAction() {
        #expect(Self.resolve("lumen://toggle/Night") == .failure(.unknownAction("toggle")))
    }

    @Test func ignoresOtherSchemes() {
        #expect(Self.resolve("https://apply/Night") == .failure(.notALumenLink))
    }

    @Test func buildsALinkThatResolvesBackToThePreset() {
        let link = PresetLink.url(for: Self.nightMode)
        #expect(link.absoluteString == "lumen://apply/Night%20Mode")
        #expect(PresetLink.action(for: link, in: Self.presets) == .success(.apply(Self.nightMode)))
    }

    @Test func errorMessagesReadNaturally() {
        #expect(PresetLinkError.noPreset("Gaming").message == "There’s no preset called “Gaming”.")
        #expect(PresetLinkError.unknownAction("toggle").message == "Lumen links can apply a preset, like lumen://apply/Night, or reconnect displays with lumen://reconnect-all.")
    }

    @Test func reconnectsAllDisplays() {
        #expect(Self.resolve("lumen://reconnect-all") == .success(.reconnectAll))
        #expect(Self.resolve("lumen://Reconnect-All/") == .success(.reconnectAll))
    }

    @Test func thereIsALinkForReconnectingAll() {
        #expect(PresetLink.reconnectAllURL.absoluteString == "lumen://reconnect-all")
    }
}
