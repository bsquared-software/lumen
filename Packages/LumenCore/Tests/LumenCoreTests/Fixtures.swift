@testable import LumenCore

extension DisplayInfo {
    static func fixture(
        uuid: String, name: String, displayID: UInt32, vendor: UInt32 = 1, model: UInt32 = 1, serial: UInt32 = 1,
        isBuiltin: Bool = false, isActive: Bool = true
    ) -> DisplayInfo {
        DisplayInfo(uuid: uuid, displayID: displayID, name: name, vendor: vendor, model: model,
                    serial: serial, isBuiltin: isBuiltin, isActive: isActive)
    }
}

/// Brandon's desk: the MacBook plus two Samsungs.
enum Desk {
    static let builtin = DisplayInfo.fixture(uuid: "BUILTIN", name: "Built-in Display", displayID: 1, isBuiltin: true)
    static let g81 = DisplayInfo.fixture(uuid: "G81", name: "Odyssey G81SF", displayID: 2)
    static let ls32 = DisplayInfo.fixture(uuid: "LS32", name: "LS32D70xE", displayID: 3)

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
