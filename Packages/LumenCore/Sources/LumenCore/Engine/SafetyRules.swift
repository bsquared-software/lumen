public enum SafetyRules {
    /// A display can be disconnected only when it is online and at least one other display
    /// stays on. Disconnecting the last display would leave the Mac with no screen at all.
    public static func canDisconnect(_ uuid: String, in displays: [KnownDisplay]) -> Bool {
        guard displays.contains(where: { $0.id == uuid && $0.status == .online }) else { return false }
        return displays.count { $0.status == .online } > 1
    }
}
