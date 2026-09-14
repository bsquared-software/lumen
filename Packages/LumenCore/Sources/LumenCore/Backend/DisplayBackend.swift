import CoreGraphics
import Foundation

public enum DisplayError: Error, Equatable, Sendable, LocalizedError {
    /// A private symbol did not resolve, most likely after a macOS update.
    case unsupported(symbol: String)
    case coreGraphics(code: Int32)
    case brightnessUnsupported
    case ddcFailed
    case modeUnavailable

    public var errorDescription: String? {
        switch self {
        case .unsupported(let symbol): "This version of macOS no longer offers \(symbol)."
        case .coreGraphics(let code): "macOS refused the display change (error \(code))."
        case .brightnessUnsupported: "Brightness can’t be controlled on this display."
        case .ddcFailed: "The monitor didn’t answer the brightness request."
        case .modeUnavailable: "That resolution isn’t available any more."
        }
    }
}

/// Everything Lumen needs from the hardware. `SystemDisplayBackend` is the only
/// implementation that touches private APIs; tests use fakes.
public protocol DisplayBackend: Sendable {
    func onlineDisplays() -> [DisplayInfo]
    /// Framebuffers in the IORegistry. A switched-off display keeps its entry; an unplugged one
    /// loses it, which is how the two are told apart.
    func attachedFramebuffers() -> [FramebufferAttributes]
    func setEnabled(_ enabled: Bool, displayID: CGDirectDisplayID) throws
    /// Normalised to `0...1`.
    func brightness(of display: DisplayInfo) throws -> Double
    func setBrightness(_ value: Double, of display: DisplayInfo) throws
    func modes(of displayID: CGDirectDisplayID) -> [DisplayMode]
    func currentMode(of displayID: CGDirectDisplayID) -> DisplayMode?
    func setMode(_ mode: DisplayMode, displayID: CGDirectDisplayID) throws
}
