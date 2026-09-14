import CoreGraphics
import Synchronization
@testable import LumenCore

/// In-memory hardware. Disconnected displays vanish from `onlineDisplays()`, like the real
/// thing, and reconnected ones reappear after `pollsUntilOnline` enumerations.
final class FakeBackend: DisplayBackend {
    enum Call: Equatable {
        case setEnabled(Bool, CGDirectDisplayID)
        case setBrightness(Double, CGDirectDisplayID)
        case setMode(DisplayMode, CGDirectDisplayID)
    }

    struct State {
        var displays: [DisplayInfo]
        var enabled: Set<CGDirectDisplayID>
        var brightness: [CGDirectDisplayID: Double] = [:]
        var calls: [Call] = []
        var pollsUntilOnline = 1
        var pendingOnline: [CGDirectDisplayID: Int] = [:]
        var neverComesBack: Set<CGDirectDisplayID> = []
        var failingDisable: Set<CGDirectDisplayID> = []
        var noBrightness: Set<CGDirectDisplayID> = []
    }

    let state: Mutex<State>

    init(displays: [DisplayInfo], enabled: [CGDirectDisplayID]? = nil) {
        state = Mutex(State(displays: displays, enabled: Set(enabled ?? displays.map(\.displayID))))
    }

    var calls: [Call] { state.withLock { $0.calls } }

    func configure(_ change: (inout State) -> Void) { state.withLock { change(&$0) } }

    func onlineDisplays() -> [DisplayInfo] {
        state.withLock { state in
            for (id, remaining) in state.pendingOnline {
                if remaining <= 1 {
                    state.pendingOnline[id] = nil
                    state.enabled.insert(id)
                } else {
                    state.pendingOnline[id] = remaining - 1
                }
            }
            return state.displays.filter { state.enabled.contains($0.displayID) }
        }
    }

    func setEnabled(_ enabled: Bool, displayID: CGDirectDisplayID) throws {
        try state.withLock { state in
            state.calls.append(.setEnabled(enabled, displayID))
            if enabled {
                guard !state.neverComesBack.contains(displayID) else { return }
                state.pendingOnline[displayID] = state.pollsUntilOnline
            } else {
                if state.failingDisable.contains(displayID) { throw DisplayError.coreGraphics(code: 1001) }
                state.enabled.remove(displayID)
            }
        }
    }

    func brightness(of display: DisplayInfo) throws -> Double {
        try state.withLock { state in
            guard !state.noBrightness.contains(display.displayID) else { throw DisplayError.brightnessUnsupported }
            return state.brightness[display.displayID] ?? 0.5
        }
    }

    func setBrightness(_ value: Double, of display: DisplayInfo) throws {
        state.withLock { state in
            state.calls.append(.setBrightness(value, display.displayID))
            state.brightness[display.displayID] = value
        }
    }

    func modes(of displayID: CGDirectDisplayID) -> [DisplayMode] { [Desk.hiDPI1440] }
    func currentMode(of displayID: CGDirectDisplayID) -> DisplayMode? { Desk.hiDPI1440 }

    func setMode(_ mode: DisplayMode, displayID: CGDirectDisplayID) throws {
        state.withLock { $0.calls.append(.setMode(mode, displayID)) }
    }
}
