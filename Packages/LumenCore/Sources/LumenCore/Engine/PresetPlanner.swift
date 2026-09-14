public enum PlanStep: Equatable, Sendable {
    case connect(uuid: String)
    /// Pause until every listed display is online again, so modes and brightness can reach it.
    case waitForOnline(uuids: [String])
    case setMode(uuid: String, mode: DisplayMode)
    case setBrightness(uuid: String, value: Double)
    case disconnect(uuid: String)
}

/// A preset entry the planner refused, with the display name for the user-facing message.
public enum PlanSkip: Equatable, Sendable {
    case notAttached(name: String)
    case builtinStaysOn(name: String)
    case wouldLeaveNoDisplay(name: String)
}

public struct PresetPlan: Equatable, Sendable {
    public var steps: [PlanStep]
    public var skipped: [PlanSkip]
}

/// Turns a preset into an ordered list of hardware steps.
///
/// Order is fixed: connect, wait, modes, brightness, disconnect. Connecting first means a
/// preset that swaps displays never passes through a moment with no screen, and values are
/// only sent to displays that are on.
public enum PresetPlanner {
    public static func plan(_ preset: Preset, displays: [KnownDisplay]) -> PresetPlan {
        let byID = Dictionary(displays.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var connects: [String] = []
        var modes: [PlanStep] = []
        var brightness: [PlanStep] = []
        var disconnects: [(uuid: String, name: String)] = []
        var skipped: [PlanSkip] = []

        for target in preset.displays {
            guard let display = byID[target.uuid], display.status != .unavailable else {
                skipped.append(.notAttached(name: target.name))
                continue
            }

            if target.connected {
                if display.status == .disconnected { connects.append(target.uuid) }
                if let mode = target.mode { modes.append(.setMode(uuid: target.uuid, mode: mode)) }
                if let value = target.brightness {
                    brightness.append(.setBrightness(uuid: target.uuid, value: min(1, max(0, value))))
                }
            } else if display.status == .online {
                if display.info.isBuiltin {
                    skipped.append(.builtinStaysOn(name: display.info.name))
                } else {
                    disconnects.append((target.uuid, display.info.name))
                }
            }
        }

        let staysOn = displays.count { $0.status == .online && !disconnects.map(\.uuid).contains($0.id) }
        if staysOn + connects.count == 0, let last = disconnects.popLast() {
            skipped.append(.wouldLeaveNoDisplay(name: last.name))
        }

        var steps: [PlanStep] = connects.map { .connect(uuid: $0) }
        if !connects.isEmpty { steps.append(.waitForOnline(uuids: connects)) }
        steps += modes + brightness + disconnects.map { .disconnect(uuid: $0.uuid) }
        return PresetPlan(steps: steps, skipped: skipped)
    }
}
