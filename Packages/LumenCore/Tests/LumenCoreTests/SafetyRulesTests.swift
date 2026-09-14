import Testing
@testable import LumenCore

@Suite struct SafetyRulesTests {
    @Test func canDisconnectWhileAnotherDisplayStaysOn() {
        #expect(SafetyRules.canDisconnect("LS32", in: Desk.allOnline))
    }

    @Test func cannotDisconnectTheOnlyActiveDisplay() {
        #expect(!SafetyRules.canDisconnect("BUILTIN", in: Desk.nightState))
    }

    @Test func cannotDisconnectADisplayThatIsNotOnline() {
        #expect(!SafetyRules.canDisconnect("LS32", in: Desk.nightState))
    }

    @Test func cannotDisconnectAnUnknownDisplay() {
        #expect(!SafetyRules.canDisconnect("NOPE", in: Desk.allOnline))
    }
}
