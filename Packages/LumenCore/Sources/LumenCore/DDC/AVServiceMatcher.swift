/// Product attributes of one framebuffer, read from the `IOMobileFramebufferShim` under a
/// `disp0@…` / `dispextN@…` device in the IORegistry.
public struct FramebufferAttributes: Equatable, Sendable {
    /// `disp0`, `dispext0`, `dispext1`, …
    public let port: String
    public let vendor: UInt32?
    public let model: UInt32?
    public let serial: UInt32?
    public let productName: String?

    public init(port: String, vendor: UInt32?, model: UInt32?, serial: UInt32?, productName: String?) {
        self.port = port
        self.vendor = vendor
        self.model = model
        self.serial = serial
        self.productName = productName
    }
}

/// Works out which DDC channel (`DCPAVServiceProxy`) belongs to which display.
///
/// Each proxy's registry path names its port (`dispext0:dcpav-service-epic`). The framebuffer
/// on that port lists the same vendor, model and serial numbers that CoreGraphics reports, so
/// the port is the join key.
public enum AVServiceMatcher {
    public static func port(fromServicePath path: String) -> String? {
        path.firstMatch(of: /(disp(?:ext)?\d+):dcpav-service/).map { String($0.1) }
    }

    public static func port(fromDeviceName name: String) -> String {
        String(name.prefix { $0 != "@" })
    }

    /// The port driving `display`, or `nil` for the built-in display and whenever the match is
    /// not unambiguous. A wrong match would send brightness to the wrong monitor, so ambiguity
    /// disables DDC instead of guessing.
    public static func port(for display: DisplayInfo, among framebuffers: [FramebufferAttributes]) -> String? {
        guard !display.isBuiltin else { return nil }
        let external = framebuffers.filter { $0.port.hasPrefix("dispext") }
        let sameProduct = external.filter { $0.vendor == display.vendor && $0.model == display.model }

        if display.serial != 0 {
            let exact = sameProduct.filter { $0.serial == display.serial }
            if exact.count == 1 { return exact[0].port }
        }
        return sameProduct.count == 1 ? sameProduct[0].port : nil
    }
}
