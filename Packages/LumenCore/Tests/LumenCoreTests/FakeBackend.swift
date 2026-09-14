import CoreGraphics
import Synchronization
@testable import LumenCore

/// In-memory hardware that mimics the real quirks: a switched-off display vanishes from
/// `onlineDisplays()` but its framebuffer stays in `attachedFramebuffers()`, and a reconnected
/// display reappears only after `pollsUntilOnline` enumerations.
final class FakeBackend: DisplayBackend {
    enum Call: Equatable {
        case setEnabled(Bool, CGDirectDisplayID)
        case setBrightness(Double, CGDirectDisplayID)
        case setMode(DisplayMode, CGDirectDisplayID)
    }

    struct State {
        var displays: [DisplayInfo]
        var enabled: Set<CGDirectDisplayID>
        var pluggedIn: Set<CGDirectDisplayID>
        var brightness: [CGDirectDisplayID: Double] = [:]
        var calls: [Call] = []
        var pollsUntilOnline = 1
        /// Enumerations a switched-off display keeps appearing for (0 on the real hardware).
        var pollsUntilOffline = 0
        var pendingOnline: [CGDirectDisplayID: Int] = [:]
        var pendingOffline: [CGDirectDisplayID: Int] = [:]
        var neverComesBack: Set<CGDirectDisplayID> = []
        var failingEnable: Set<CGDirectDisplayID> = []
        var failingDisable: Set<CGDirectDisplayID> = []
        var noBrightness: Set<CGDirectDisplayID> = []
    }

    let state: Mutex<State>

    init(displays: [DisplayInfo], enabled: [CGDirectDisplayID]? = nil) {
        let all = Set(displays.map(\.displayID))
        state = Mutex(State(displays: displays, enabled: enabled.map(Set.init) ?? all, pluggedIn: all))
    }

    var calls: [Call] { state.withLock { $0.calls } }

    func configure(_ change: (inout State) -> Void) { state.withLock { change(&$0) } }

    func onlineDisplays() -> [DisplayInfo] {
        state.withLock { state in
            for (id, remaining) in state.pendingOnline {
                if remaining <= 1 { state.pendingOnline[id] = nil; state.enabled.insert(id) } else { state.pendingOnline[id] = remaining - 1 }
            }
            let lingering = Set(state.pendingOffline.keys)
            for (id, remaining) in state.pendingOffline {
                state.pendingOffline[id] = remaining <= 1 ? nil : remaining - 1
            }
            return state.displays.filter { state.enabled.contains($0.displayID) || lingering.contains($0.displayID) }
        }
    }

    func attachedFramebuffers() -> [FramebufferAttributes] {
        state.withLock { state in
            state.displays.filter { state.pluggedIn.contains($0.displayID) }.map {
                Desk.framebuffer($0, port: $0.isBuiltin ? "disp0" : "dispext\($0.displayID)")
            }
        }
    }

    func setEnabled(_ enabled: Bool, displayID: CGDirectDisplayID) throws {
        try state.withLock { state in
            state.calls.append(.setEnabled(enabled, displayID))
            if enabled {
                if state.failingEnable.contains(displayID) { throw DisplayError.coreGraphics(code: 1000) }
                guard !state.neverComesBack.contains(displayID) else { return }
                state.pendingOnline[displayID] = state.pollsUntilOnline
            } else {
                if state.failingDisable.contains(displayID) { throw DisplayError.coreGraphics(code: 1001) }
                state.enabled.remove(displayID)
                if state.pollsUntilOffline > 0 { state.pendingOffline[displayID] = state.pollsUntilOffline }
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
        try state.withLock { state in
            guard !state.noBrightness.contains(display.displayID) else { throw DisplayError.brightnessUnsupported }
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
