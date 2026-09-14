import Foundation
import Testing
@testable import LumenCore

@Suite struct PresetLinkTests {
    static let nightMode = Preset(name: "Night Mode", symbol: "moon", displays: [])
    static let presets = [Desk.night, Desk.day, nightMode]

    static func resolve(_ link: String) -> Result<Preset, PresetLinkError> {
        PresetLink.resolve(URL(string: link)!, in: presets)
    }

    @Test func appliesAPresetByName() {
        #expect(Self.resolve("lumen://apply/Night") == .success(Desk.night))
    }

    @Test func namesAreCaseInsensitive() {
        #expect(Self.resolve("lumen://apply/day") == .success(Desk.day))
    }

    @Test func namesMayContainSpaces() {
        #expect(Self.resolve("lumen://apply/Night%20Mode") == .success(Self.nightMode))
    }

    @Test func appliesAPresetByID() {
        #expect(Self.resolve("lumen://apply/\(Desk.day.id.uuidString)") == .success(Desk.day))
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
        #expect(PresetLink.resolve(link, in: Self.presets) == .success(Self.nightMode))
    }

    @Test func errorMessagesReadNaturally() {
        #expect(PresetLinkError.noPreset("Gaming").message == "There’s no preset called “Gaming”.")
        #expect(PresetLinkError.unknownAction("toggle").message == "Lumen links can only apply presets, like lumen://apply/Night.")
    }
}
