import Testing
@testable import LumenCore

@Suite struct AVServiceMatcherTests {
    // Real values from this MacBook's IORegistry and CoreGraphics on 2026-09-14.
    static let ls32 = DisplayInfo.fixture(uuid: "E292FE42", name: "LS32D70xE", displayID: 3, vendor: 19501, model: 30291, serial: 809582919)
    static let g81 = DisplayInfo.fixture(uuid: "11F14D77", name: "Odyssey G81SF", displayID: 2, vendor: 19501, model: 30540, serial: 811091798)
    static let builtin = DisplayInfo.fixture(uuid: "37D8832A", name: "Built-in Display", displayID: 1, vendor: 1552, model: 41040, serial: 4251086178, isBuiltin: true)

    static let realFramebuffers = [
        FramebufferAttributes(port: "dispext0", vendor: 19501, model: 30291, serial: 809582919, productName: "LS32D70xE"),
        FramebufferAttributes(port: "dispext1", vendor: 19501, model: 30540, serial: 811091798, productName: "Odyssey G81SF"),
        FramebufferAttributes(port: "disp0", vendor: 1552, model: nil, serial: nil, productName: nil),
    ]

    @Test func extractsExternalPortFromServicePath() {
        let path = "IOService:/AppleARMPE/arm-io@10F00000/AppleT603xIO/dispext0@C0000000/AppleDCPEXT0Endpoint9/AFKEPInterfaceServiceKextV2/dispext0:dcpav-service-epic:0/DCPAVServiceProxy"
        #expect(AVServiceMatcher.port(fromServicePath: path) == "dispext0")
    }

    @Test func extractsBuiltinPortFromServicePath() {
        let path = "IOService:/AppleARMPE/arm-io/AFKEPInterfaceServiceKextV2/disp0:dcpav-service-epic:0/DCPAVServiceProxy"
        #expect(AVServiceMatcher.port(fromServicePath: path) == "disp0")
    }

    @Test func ignoresUnrelatedServicePath() {
        #expect(AVServiceMatcher.port(fromServicePath: "IOService:/AppleARMPE/arm-io/usb-drd0") == nil)
    }

    @Test func extractsPortFromDeviceName() {
        #expect(AVServiceMatcher.port(fromDeviceName: "dispext1@C4000000") == "dispext1")
        #expect(AVServiceMatcher.port(fromDeviceName: "dispext1") == "dispext1")
    }

    @Test func matchesRealMonitorsToTheirPorts() {
        #expect(AVServiceMatcher.port(for: Self.ls32, among: Self.realFramebuffers) == "dispext0")
        #expect(AVServiceMatcher.port(for: Self.g81, among: Self.realFramebuffers) == "dispext1")
    }

    @Test func builtinDisplayHasNoDDCPort() {
        #expect(AVServiceMatcher.port(for: Self.builtin, among: Self.realFramebuffers) == nil)
    }

    @Test func twinMonitorsMatchBySerial() {
        let left = DisplayInfo.fixture(uuid: "L", name: "Twin", displayID: 2, vendor: 1, model: 2, serial: 111)
        let right = DisplayInfo.fixture(uuid: "R", name: "Twin", displayID: 3, vendor: 1, model: 2, serial: 222)
        let framebuffers = [
            FramebufferAttributes(port: "dispext0", vendor: 1, model: 2, serial: 222, productName: "Twin"),
            FramebufferAttributes(port: "dispext1", vendor: 1, model: 2, serial: 111, productName: "Twin"),
        ]
        #expect(AVServiceMatcher.port(for: left, among: framebuffers) == "dispext1")
        #expect(AVServiceMatcher.port(for: right, among: framebuffers) == "dispext0")
    }

    @Test func zeroSerialFallsBackToVendorAndModelWhenUnique() {
        let display = DisplayInfo.fixture(uuid: "Z", name: "No serial", displayID: 2, vendor: 1, model: 2, serial: 0)
        let framebuffers = [
            FramebufferAttributes(port: "dispext0", vendor: 1, model: 2, serial: 0, productName: nil),
            FramebufferAttributes(port: "dispext1", vendor: 9, model: 9, serial: 9, productName: nil),
        ]
        #expect(AVServiceMatcher.port(for: display, among: framebuffers) == "dispext0")
    }

    @Test func ambiguousTwinsWithoutSerialsDoNotMatch() {
        let display = DisplayInfo.fixture(uuid: "Z", name: "No serial", displayID: 2, vendor: 1, model: 2, serial: 0)
        let framebuffers = [
            FramebufferAttributes(port: "dispext0", vendor: 1, model: 2, serial: 0, productName: nil),
            FramebufferAttributes(port: "dispext1", vendor: 1, model: 2, serial: 0, productName: nil),
        ]
        #expect(AVServiceMatcher.port(for: display, among: framebuffers) == nil)
    }
}

extension DisplayInfo {
    static func fixture(
        uuid: String, name: String, displayID: UInt32, vendor: UInt32, model: UInt32, serial: UInt32,
        isBuiltin: Bool = false, isActive: Bool = true
    ) -> DisplayInfo {
        DisplayInfo(uuid: uuid, displayID: displayID, name: name, vendor: vendor, model: model,
                    serial: serial, isBuiltin: isBuiltin, isActive: isActive)
    }
}
