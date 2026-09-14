/// Merges what CoreGraphics reports now with what Lumen remembers.
///
/// A display Lumen disconnected may vanish from CoreGraphics entirely, so the saved record is
/// the only way to show it and switch it back on.
public enum DisplayRegistry {
    public static func merge(records: [DisplayRecord], online: [DisplayInfo]) -> [DisplayRecord] {
        var merged = records
        for info in online {
            if let index = merged.firstIndex(where: { $0.id == info.uuid }) {
                merged[index].info = info
                if info.isActive { merged[index].disconnectedByLumen = false }
            } else {
                merged.append(DisplayRecord(info: info, disconnectedByLumen: false))
            }
        }
        return merged
    }

    /// Every remembered display with its status, built-in first.
    public static func knownDisplays(records: [DisplayRecord], online: [DisplayInfo]) -> [KnownDisplay] {
        let onlineByID = Dictionary(online.map { ($0.uuid, $0) }, uniquingKeysWith: { first, _ in first })
        let known = merge(records: records, online: online).map { record in
            let current = onlineByID[record.id]
            return KnownDisplay(info: current ?? record.info, status: DisplayStatus.resolve(record: record, online: current))
        }
        return known.filter(\.info.isBuiltin) + known.filter { !$0.info.isBuiltin }
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
