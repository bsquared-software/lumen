import ColorSync
import CoreGraphics
import Foundation
import Synchronization

/// The real hardware backend: CoreGraphics for enumeration and modes, SkyLight's
/// `CGSConfigureDisplayEnabled` for connect/disconnect, DisplayServices for Apple panels and
/// DDC/CI over IOAVService for other monitors.
public final class SystemDisplayBackend: DisplayBackend {
    /// DDC maximum per display UUID, so a brightness write does not need a read first.
    private let ddcMaximums = Mutex<[String: UInt16]>([:])

    public init() {}

    // MARK: Enumeration

    public func onlineDisplays() -> [DisplayInfo] {
        var ids = [CGDirectDisplayID](repeating: 0, count: 32)
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(UInt32(ids.count), &ids, &count) == .success else { return [] }
        let framebuffers = IORegistryScanner.framebufferAttributes()

        return ids.prefix(Int(count)).compactMap { id in
            guard let cfUUID = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue(),
                  let uuid = CFUUIDCreateString(nil, cfUUID) as String?
            else { return nil }

            var info = DisplayInfo(
                uuid: uuid, displayID: id, name: "Display \(id)",
                vendor: CGDisplayVendorNumber(id), model: CGDisplayModelNumber(id), serial: CGDisplaySerialNumber(id),
                isBuiltin: CGDisplayIsBuiltin(id) != 0,
                originX: Int(CGDisplayBounds(id).origin.x)
            )
            if info.isBuiltin {
                info.name = "Built-in Display"
            } else if let port = AVServiceMatcher.port(for: info, among: framebuffers),
                      let name = framebuffers.first(where: { $0.port == port })?.productName {
                info.name = name
            }
            return info
        }
    }

    public func attachedFramebuffers() -> [FramebufferAttributes] {
        IORegistryScanner.framebufferAttributes()
    }

    // MARK: Connection

    public func setEnabled(_ enabled: Bool, displayID: CGDirectDisplayID) throws {
        guard let configure = PrivateSymbols.configureDisplayEnabled else {
            throw DisplayError.unsupported(symbol: "CGSConfigureDisplayEnabled")
        }
        try configureDisplays(option: .forSession) { config in
            configure(config, displayID, enabled)
        }
    }

    // MARK: Brightness

    public func brightness(of display: DisplayInfo) throws -> Double {
        if usesDisplayServices(display) {
            guard let get = PrivateSymbols.getBrightness else { throw DisplayError.unsupported(symbol: "DisplayServicesGetBrightness") }
            var value: Float = 0
            guard get(display.displayID, &value) == 0 else { throw DisplayError.brightnessUnsupported }
            return Double(value)
        }
        let value = try readVCP(DDCPacket.brightnessVCP, of: display)
        ddcMaximums.withLock { $0[display.uuid] = value.maximum }
        return value.normalised
    }

    public func setBrightness(_ value: Double, of display: DisplayInfo) throws {
        let clamped = min(1, max(0, value))
        if usesDisplayServices(display) {
            guard let set = PrivateSymbols.setBrightness else { throw DisplayError.unsupported(symbol: "DisplayServicesSetBrightness") }
            guard set(display.displayID, Float(clamped)) == 0 else { throw DisplayError.brightnessUnsupported }
            return
        }
        let knownMaximum = ddcMaximums.withLock { $0[display.uuid] }
        let maximum = try knownMaximum ?? readVCP(DDCPacket.brightnessVCP, of: display).maximum
        ddcMaximums.withLock { $0[display.uuid] = maximum }
        try writeVCP(DDCPacket.brightnessVCP, value: VCPValue.raw(forNormalised: clamped, maximum: maximum), of: display)
    }

    private func usesDisplayServices(_ display: DisplayInfo) -> Bool {
        display.isBuiltin || PrivateSymbols.canChangeBrightness?(display.displayID) == true
    }

    // MARK: Modes

    public func modes(of displayID: CGDirectDisplayID) -> [DisplayMode] {
        usableModes(of: displayID).map(DisplayMode.init)
    }

    public func currentMode(of displayID: CGDirectDisplayID) -> DisplayMode? {
        CGDisplayCopyDisplayMode(displayID).map(DisplayMode.init)
    }

    public func setMode(_ mode: DisplayMode, displayID: CGDirectDisplayID) throws {
        // Reconfiguring to the mode already in use still blanks the display for a moment.
        if let current = currentMode(of: displayID), current.matches(mode) { return }
        guard let target = usableModes(of: displayID).first(where: { DisplayMode($0).matches(mode) }) else {
            throw DisplayError.modeUnavailable
        }
        // `.permanently` matches System Settings: the resolution survives a restart.
        try configureDisplays(option: .permanently) { config in
            CGConfigureDisplayWithDisplayMode(config, displayID, target, nil).rawValue
        }
    }

    private func usableModes(of displayID: CGDirectDisplayID) -> [CGDisplayMode] {
        let options = [kCGDisplayShowDuplicateLowResolutionModes: true] as CFDictionary
        let modes = CGDisplayCopyAllDisplayModes(displayID, options) as? [CGDisplayMode] ?? []
        return modes.filter { $0.isUsableForDesktopGUI() }
    }

    // MARK: Helpers

    private func configureDisplays(option: CGConfigureOption, _ change: (CGDisplayConfigRef) -> Int32) throws {
        var config: CGDisplayConfigRef?
        let began = CGBeginDisplayConfiguration(&config)
        guard began == .success, let config else { throw DisplayError.coreGraphics(code: began.rawValue) }

        let changed = change(config)
        guard changed == 0 else {
            CGCancelDisplayConfiguration(config)
            throw DisplayError.coreGraphics(code: changed)
        }
        let completed = CGCompleteDisplayConfiguration(config, option)
        guard completed == .success else { throw DisplayError.coreGraphics(code: completed.rawValue) }
    }

    private func readVCP(_ vcp: UInt8, of display: DisplayInfo) throws -> VCPValue {
        guard let read = PrivateSymbols.avServiceReadI2C, let write = PrivateSymbols.avServiceWriteI2C else {
            throw DisplayError.unsupported(symbol: "IOAVServiceReadI2C")
        }
        return try withAVService(for: display) { service in
            for attempt in 1...3 {
                var request = DDCPacket.getVCPRequest(vcp)
                let wrote = request.withUnsafeMutableBytes {
                    write(service, DDCPacket.chipAddress, DDCPacket.dataAddress, $0.baseAddress!, UInt32($0.count))
                }
                usleep(50_000)
                var reply = [UInt8](repeating: 0, count: DDCPacket.replyLength + 1)
                let didRead = reply.withUnsafeMutableBytes {
                    read(service, DDCPacket.chipAddress, DDCPacket.dataAddress, $0.baseAddress!, UInt32($0.count))
                }
                if wrote == KERN_SUCCESS, didRead == KERN_SUCCESS,
                   let value = try? DDCPacket.parseGetVCPReply(reply, vcp: vcp) {
                    return value
                }
                if attempt < 3 { usleep(40_000) }
            }
            throw DisplayError.ddcFailed
        }
    }

    private func writeVCP(_ vcp: UInt8, value: UInt16, of display: DisplayInfo) throws {
        guard let write = PrivateSymbols.avServiceWriteI2C else { throw DisplayError.unsupported(symbol: "IOAVServiceWriteI2C") }
        try withAVService(for: display) { service in
            for attempt in 1...3 {
                var request = DDCPacket.setVCPRequest(vcp, value: value)
                let wrote = request.withUnsafeMutableBytes {
                    write(service, DDCPacket.chipAddress, DDCPacket.dataAddress, $0.baseAddress!, UInt32($0.count))
                }
                if wrote == KERN_SUCCESS { return }
                if attempt < 3 { usleep(40_000) }
            }
            throw DisplayError.ddcFailed
        }
    }

    private func withAVService<Result>(for display: DisplayInfo, _ body: (UnsafeMutableRawPointer) throws -> Result) throws -> Result {
        guard let port = AVServiceMatcher.port(for: display, among: IORegistryScanner.framebufferAttributes()) else {
            throw DisplayError.brightnessUnsupported
        }
        return try IORegistryScanner.withAVService(port: port, body)
    }
}

extension DisplayMode {
    init(_ mode: CGDisplayMode) {
        self.init(width: mode.width, height: mode.height, pixelWidth: mode.pixelWidth,
                  pixelHeight: mode.pixelHeight, refreshRate: mode.refreshRate)
    }
}
