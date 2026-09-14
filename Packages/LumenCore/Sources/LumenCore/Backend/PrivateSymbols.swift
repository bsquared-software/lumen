import CoreGraphics
import Darwin
import IOKit

/// Private functions, resolved at runtime with `dlsym` and called through C function
/// pointers. Each one is optional: a macOS update that removes a symbol degrades that one
/// feature instead of crashing the app.
///
/// Signatures follow the ones BetterDisplay, MonitorControl and displayplacer rely on.
/// Verified present on macOS 27.0 (26A428), 2026-09-14.
enum PrivateSymbols {
    typealias ConfigureDisplayEnabled = @convention(c) (CGDisplayConfigRef, CGDirectDisplayID, Bool) -> Int32
    typealias CanChangeBrightness = @convention(c) (CGDirectDisplayID) -> Bool
    typealias GetBrightness = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    typealias SetBrightness = @convention(c) (CGDirectDisplayID, Float) -> Int32
    /// Returns a +1 retained `IOAVServiceRef`.
    typealias AVServiceCreate = @convention(c) (CFAllocator?, io_service_t) -> UnsafeMutableRawPointer?
    typealias AVServiceI2C = @convention(c) (UnsafeMutableRawPointer, UInt32, UInt32, UnsafeMutableRawPointer, UInt32) -> IOReturn

    private static let coreGraphics = "/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics"
    private static let displayServices = "/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices"
    private static let ioKit = "/System/Library/Frameworks/IOKit.framework/IOKit"

    static let configureDisplayEnabled = load("CGSConfigureDisplayEnabled", from: coreGraphics, as: ConfigureDisplayEnabled.self)
    static let canChangeBrightness = load("DisplayServicesCanChangeBrightness", from: displayServices, as: CanChangeBrightness.self)
    static let getBrightness = load("DisplayServicesGetBrightness", from: displayServices, as: GetBrightness.self)
    static let setBrightness = load("DisplayServicesSetBrightness", from: displayServices, as: SetBrightness.self)
    static let avServiceCreate = load("IOAVServiceCreateWithService", from: ioKit, as: AVServiceCreate.self)
    static let avServiceReadI2C = load("IOAVServiceReadI2C", from: ioKit, as: AVServiceI2C.self)
    static let avServiceWriteI2C = load("IOAVServiceWriteI2C", from: ioKit, as: AVServiceI2C.self)

    private static func load<Function>(_ name: String, from path: String, as type: Function.Type) -> Function? {
        guard let handle = dlopen(path, RTLD_LAZY | RTLD_NOLOAD) ?? dlopen(path, RTLD_LAZY),
              let symbol = dlsym(handle, name)
        else { return nil }
        return unsafeBitCast(symbol, to: type)
    }
}
