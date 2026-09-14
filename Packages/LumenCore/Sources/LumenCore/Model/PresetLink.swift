import Foundation

public enum PresetLinkError: Error, Equatable, Sendable {
    case notALumenLink
    case unknownAction(String)
    case noPreset(String)

    public var message: String {
        switch self {
        case .notALumenLink: "That isn’t a Lumen link."
        case .unknownAction: "Lumen links can apply a preset, like lumen://apply/Night, or reconnect displays with lumen://reconnect-all."
        case .noPreset(let name): "There’s no preset called “\(name)”."
        }
    }
}

/// What a Lumen link asks for.
public enum LinkAction: Equatable, Sendable {
    case apply(Preset)
    case reconnectAll
}

/// `lumen://apply/<preset name or ID>` and `lumen://reconnect-all` links, so Shortcuts, Raycast,
/// a Stream Deck or a scheduled `open` can drive Lumen.
public enum PresetLink {
    public static let scheme = "lumen"
    static let applyAction = "apply"
    static let reconnectAllAction = "reconnect-all"

    public static var reconnectAllURL: URL {
        URL(string: "\(scheme)://\(reconnectAllAction)")!
    }

    public static func url(for preset: Preset) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = applyAction
        components.path = "/" + preset.name
        return components.url!
    }

    /// Presets match by ID first, then by name, ignoring case.
    public static func action(for url: URL, in presets: [Preset]) -> Result<LinkAction, PresetLinkError> {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == scheme
        else { return .failure(.notALumenLink) }

        let action = components.host ?? ""
        let reference = String(components.path.drop { $0 == "/" })

        switch action.lowercased() {
        case reconnectAllAction:
            return .success(.reconnectAll)
        case applyAction:
            if let id = UUID(uuidString: reference), let preset = presets.first(where: { $0.id == id }) {
                return .success(.apply(preset))
            }
            if let preset = presets.first(where: { $0.name.caseInsensitiveCompare(reference) == .orderedSame }) {
                return .success(.apply(preset))
            }
            return .failure(.noPreset(reference))
        default:
            return .failure(.unknownAction(action))
        }
    }
}
