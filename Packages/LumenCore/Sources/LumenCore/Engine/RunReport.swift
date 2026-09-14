import Foundation

public enum FailureReason: Equatable, Sendable {
    /// Switched back on, but never reappeared within the timeout.
    case didNotComeBack
    /// A value was meant for a display that is not on.
    case notOnline
    /// The backend threw; carries the user-facing message.
    case backend(String)
}

public struct DisplayFailure: Equatable, Sendable {
    public let name: String
    public let reason: FailureReason

    public init(name: String, reason: FailureReason) {
        self.name = name
        self.reason = reason
    }

    static func backend(_ name: String, _ error: any Error) -> DisplayFailure {
        DisplayFailure(name: name, reason: .backend((error as? LocalizedError)?.errorDescription ?? String(describing: error)))
    }
}

/// What happened when Lumen tried to change the displays, in terms the user can act on.
public struct RunReport: Equatable, Sendable {
    public var skipped: [PlanSkip]
    public var failures: [DisplayFailure]
    /// Set to the preset's name when none of its displays were plugged in, so nothing happened.
    public var unattachedPreset: String?

    public init(skipped: [PlanSkip] = [], failures: [DisplayFailure] = [], unattachedPreset: String? = nil) {
        self.skipped = skipped
        self.failures = failures
        self.unattachedPreset = unattachedPreset
    }

    public var isClean: Bool { skipped.isEmpty && failures.isEmpty }

    /// Displays that are simply unplugged don't get a message: applying Night on the laptop
    /// alone would otherwise complain about every monitor, every time.
    public var messages: [String] {
        let unattached = unattachedPreset.map { ["None of \($0)’s displays are plugged in, so nothing changed."] } ?? []
        let skips: [String] = skipped.compactMap { skip in
            switch skip {
            case .notAttached: nil
            case .builtinStaysOn: "The built-in display always stays on in presets."
            case .wouldLeaveNoDisplay(let name): "\(name) stayed on so you’re not left without a screen."
            }
        }
        let problems = failures.map { failure in
            switch failure.reason {
            case .didNotComeBack: "\(failure.name) didn’t come back. Try unplugging it and plugging it in again."
            case .notOnline: "\(failure.name) is off, so its settings weren’t changed."
            case .backend(let message): "\(failure.name): \(message)"
            }
        }
        return unattached + skips + problems
    }
}
