/// What Lumen remembers about a display between launches.
public struct DisplayRecord: Codable, Hashable, Sendable, Identifiable {
    public var id: String { info.uuid }

    /// The last known details, including the session display ID needed to reconnect it.
    public var info: DisplayInfo
    /// Set when Lumen disconnects the display, cleared when it next comes online. A display
    /// that vanishes without this flag was unplugged.
    public var disconnectedByLumen: Bool

    public init(info: DisplayInfo, disconnectedByLumen: Bool) {
        self.info = info
        self.disconnectedByLumen = disconnectedByLumen
    }
}

public enum DisplayStatus: String, Codable, Sendable {
    /// macOS is drawing to it.
    case online
    /// Attached, but switched off in software. It can be switched back on.
    case disconnected
    /// Remembered but not attached (unplugged). Nothing Lumen can do.
    case unavailable

    /// - Parameter isAttached: whether the display's framebuffer is still in the IORegistry.
    ///   A switched-off display keeps it (verified on hardware); an unplugged one should not.
    public static func resolve(record: DisplayRecord, online: DisplayInfo?, isAttached: Bool) -> DisplayStatus {
        if online != nil { return .online }
        return record.disconnectedByLumen && isAttached ? .disconnected : .unavailable
    }
}

/// A display with its current status, the unit the planner and UI work with.
public struct KnownDisplay: Hashable, Sendable, Identifiable {
    public var id: String { info.uuid }

    public var info: DisplayInfo
    public var status: DisplayStatus

    public init(info: DisplayInfo, status: DisplayStatus) {
        self.info = info
        self.status = status
    }
}
