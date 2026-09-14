import Foundation
import IOKit

/// Reads the two IORegistry facts DDC needs: which product sits on each display port, and the
/// DDC channel (`DCPAVServiceProxy`) for each external port.
enum IORegistryScanner {
    static func framebufferAttributes() -> [FramebufferAttributes] {
        services(matching: "IOMobileFramebufferShim").compactMap { service in
            defer { IOObjectRelease(service) }
            var parent: io_registry_entry_t = 0
            guard IORegistryEntryGetParentEntry(service, kIOServicePlane, &parent) == KERN_SUCCESS else { return nil }
            defer { IOObjectRelease(parent) }

            var name = [CChar](repeating: 0, count: 128)
            guard IORegistryEntryGetName(parent, &name) == KERN_SUCCESS else { return nil }
            let port = AVServiceMatcher.port(fromDeviceName: string(from: name))

            let attributes = property(service, "DisplayAttributes") as? [String: Any]
            let product = attributes?["ProductAttributes"] as? [String: Any]
            return FramebufferAttributes(
                port: port,
                vendor: uint32(product?["LegacyManufacturerID"]),
                model: uint32(product?["ProductID"]),
                serial: uint32(product?["SerialNumber"]),
                productName: product?["ProductName"] as? String
            )
        }
    }

    /// Runs `body` with the IOAVService for an external port, releasing it afterwards.
    static func withAVService<Result>(port: String, _ body: (UnsafeMutableRawPointer) throws -> Result) throws -> Result {
        guard let create = PrivateSymbols.avServiceCreate else { throw DisplayError.unsupported(symbol: "IOAVServiceCreateWithService") }

        for service in services(matching: "DCPAVServiceProxy") {
            defer { IOObjectRelease(service) }
            guard property(service, "Location") as? String == "External" else { continue }

            var path = [CChar](repeating: 0, count: 1024)
            guard IORegistryEntryGetPath(service, kIOServicePlane, &path) == KERN_SUCCESS,
                  AVServiceMatcher.port(fromServicePath: string(from: path)) == port,
                  let avService = create(kCFAllocatorDefault, service)
            else { continue }

            defer { Unmanaged<AnyObject>.fromOpaque(avService).release() }
            return try body(avService)
        }
        throw DisplayError.brightnessUnsupported
    }

    private static func services(matching className: String) -> [io_service_t] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(className), &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }
        var found: [io_service_t] = []
        while case let service = IOIteratorNext(iterator), service != 0 {
            found.append(service)
        }
        return found
    }

    private static func property(_ entry: io_registry_entry_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }

    private static func string(from buffer: [CChar]) -> String {
        String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    private static func uint32(_ value: Any?) -> UInt32? {
        (value as? NSNumber).flatMap { UInt32(exactly: $0.uint64Value) }
    }
}
