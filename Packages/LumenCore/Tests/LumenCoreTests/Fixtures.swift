@testable import LumenCore

extension DisplayInfo {
    static func fixture(
        uuid: String, name: String, displayID: UInt32, vendor: UInt32 = 1, model: UInt32 = 1, serial: UInt32 = 1,
        isBuiltin: Bool = false, originX: Int? = nil
    ) -> DisplayInfo {
        DisplayInfo(uuid: uuid, displayID: displayID, name: name, vendor: vendor, model: model,
                    serial: serial, isBuiltin: isBuiltin, originX: originX)
    }
}

/// Brandon's desk: the MacBook plus two Samsungs.
enum Desk {
    // The real arrangement: G81SF on the left, MacBook in the middle, LS32D70xE on the right.
    static let builtin = DisplayInfo.fixture(uuid: "BUILTIN", name: "Built-in Display", displayID: 1, vendor: 1552, model: 41040, serial: 9, isBuiltin: true, originX: 0)
    static let g81 = DisplayInfo.fixture(uuid: "G81", name: "Odyssey G81SF", displayID: 2, vendor: 19501, model: 30540, serial: 811091798, originX: -2048)
    static let ls32 = DisplayInfo.fixture(uuid: "LS32", name: "LS32D70xE", displayID: 3, vendor: 19501, model: 30291, serial: 809582919, originX: 1728)

    static func framebuffer(_ info: DisplayInfo, port: String) -> FramebufferAttributes {
        FramebufferAttributes(port: port, vendor: info.vendor, model: info.model, serial: info.serial, productName: info.name)
    }

    /// What the IORegistry lists while all three are plugged in, switched on or not.
    static let pluggedIn = [framebuffer(builtin, port: "disp0"), framebuffer(ls32, port: "dispext0"), framebuffer(g81, port: "dispext1")]

    static func known(_ info: DisplayInfo, _ status: DisplayStatus) -> KnownDisplay {
        KnownDisplay(info: info, status: status)
    }

    static let allOnline = [known(g81, .online), known(ls32, .online), known(builtin, .online)]
    static let nightState = [known(g81, .disconnected), known(ls32, .disconnected), known(builtin, .online)]

    static let hiDPI1440 = DisplayMode(width: 2560, height: 1440, pixelWidth: 5120, pixelHeight: 2880, refreshRate: 120)

    static let night = Preset(
        name: "Night", symbol: "moon.stars",
        displays: [
            DisplayTarget(uuid: "G81", name: "Odyssey G81SF", connected: false),
            DisplayTarget(uuid: "LS32", name: "LS32D70xE", connected: false),
            DisplayTarget(uuid: "BUILTIN", name: "Built-in Display", connected: true, brightness: 0.10),
        ]
    )

    static let day = Preset(
        name: "Day", symbol: "sun.max",
        displays: [
            DisplayTarget(uuid: "G81", name: "Odyssey G81SF", connected: true, mode: hiDPI1440),
            DisplayTarget(uuid: "LS32", name: "LS32D70xE", connected: true),
            DisplayTarget(uuid: "BUILTIN", name: "Built-in Display", connected: true, brightness: 0.6),
        ]
    )
}
