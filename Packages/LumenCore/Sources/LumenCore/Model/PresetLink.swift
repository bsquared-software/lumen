import Foundation

public enum PresetLinkError: Error, Equatable, Sendable {
    case notALumenLink
    case unknownAction(String)
    case noPreset(String)

    public var message: String {
        switch self {
        case .notALumenLink: "That isn’t a Lumen link."
        case .unknownAction: "Lumen links can only apply presets, like lumen://apply/Night."
        case .noPreset(let name): "There’s no preset called “\(name)”."
        }
    }
}

/// `lumen://apply/<preset name or ID>` links, so Shortcuts, Raycast, a Stream Deck or a
/// scheduled `open` can apply presets.
public enum PresetLink {
    public static let scheme = "lumen"
    static let applyAction = "apply"

    public static func url(for preset: Preset) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = applyAction
        components.path = "/" + preset.name
        return components.url!
    }

    /// Matches the preset ID first, then the name, ignoring case.
    public static func resolve(_ url: URL, in presets: [Preset]) -> Result<Preset, PresetLinkError> {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == scheme
        else { return .failure(.notALumenLink) }

        let action = components.host ?? ""
        guard action.lowercased() == applyAction else { return .failure(.unknownAction(action)) }

        let reference = String(components.path.drop { $0 == "/" })
        if let id = UUID(uuidString: reference), let preset = presets.first(where: { $0.id == id }) {
            return .success(preset)
        }
        if let preset = presets.first(where: { $0.name.caseInsensitiveCompare(reference) == .orderedSame }) {
            return .success(preset)
        }
        return .failure(.noPreset(reference))
    }
}
