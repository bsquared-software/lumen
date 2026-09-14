/// Merges what CoreGraphics reports now with what Lumen remembers.
///
/// A display Lumen switched off vanishes from CoreGraphics entirely, so the saved record is the
/// only way to show it and switch it back on.
public enum DisplayRegistry {
    /// - Parameter keepingFlagsFor: displays being switched off right now. They may still be
    ///   listed for a moment, and must not lose their flag while they are.
    public static func merge(records: [DisplayRecord], online: [DisplayInfo], keepingFlagsFor switchingOff: Set<String> = []) -> [DisplayRecord] {
        var merged = records
        for info in online {
            if let index = merged.firstIndex(where: { $0.id == info.uuid }) {
                merged[index].info = info
                if !switchingOff.contains(info.uuid) { merged[index].disconnectedByLumen = false }
            } else {
                merged.append(DisplayRecord(info: info, disconnectedByLumen: false))
            }
        }
        return merged
    }

    /// Every remembered display with its status, left to right as arranged on the desk. Displays
    /// with no known position follow, in the order they were first seen.
    public static func knownDisplays(
        records: [DisplayRecord], online: [DisplayInfo], framebuffers: [FramebufferAttributes],
        switchingOff: Set<String> = []
    ) -> [KnownDisplay] {
        let onlineByID = Dictionary(online.map { ($0.uuid, $0) }, uniquingKeysWith: { first, _ in first })
        let known = merge(records: records, online: online, keepingFlagsFor: switchingOff).map { record in
            let current = switchingOff.contains(record.id) ? nil : onlineByID[record.id]
            let status = DisplayStatus.resolve(record: record, online: current, isAttached: isAttached(record.info, framebuffers: framebuffers))
            return KnownDisplay(info: current ?? record.info, status: status, customName: record.customName)
        }
        return known.enumerated()
            .sorted { lhs, rhs in
                switch (lhs.element.info.originX, rhs.element.info.originX) {
                case let (left?, right?) where left != right: left < right
                case (.some, nil): true
                case (nil, .some): false
                default: lhs.offset < rhs.offset
                }
            }
            .map(\.element)
    }

    public static func isAttached(_ info: DisplayInfo, framebuffers: [FramebufferAttributes]) -> Bool {
        if info.isBuiltin { return framebuffers.contains { $0.port == "disp0" } }
        return AVServiceMatcher.port(for: info, among: framebuffers) != nil
    }

    public static func setDisconnectedByLumen(_ flag: Bool, uuid: String, in records: [DisplayRecord]) -> [DisplayRecord] {
        records.map { record in
            guard record.id == uuid else { return record }
            var updated = record
            updated.disconnectedByLumen = flag
            return updated
        }
    }
}
