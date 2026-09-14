import Foundation
import LumenCore

// Hardware harness for LumenCore's SystemDisplayBackend. Not shipped in the app.
//
//   lumen-probe list
//   lumen-probe modes <uuid-prefix>
//   lumen-probe brightness <uuid-prefix> [0...1]
//   lumen-probe blink <uuid-prefix> <seconds>     disconnects, waits, reconnects

let backend = SystemDisplayBackend()
let arguments = Array(CommandLine.arguments.dropFirst())

func find(_ prefix: String) -> DisplayInfo {
    guard let display = backend.onlineDisplays().first(where: { $0.uuid.hasPrefix(prefix.uppercased()) }) else {
        print("No online display with a UUID starting \(prefix)")
        exit(1)
    }
    return display
}

func describe(_ displays: [DisplayInfo]) {
    for display in displays {
        let brightness = (try? backend.brightness(of: display)).map { String(format: "%.0f%%", $0 * 100) } ?? "n/a"
        let mode = backend.currentMode(of: display.displayID)
            .map { "\($0.width)x\($0.height)\($0.isHiDPI ? " HiDPI" : "") @ \(ModeCatalogue.refreshLabel($0.refreshRate))" } ?? "none"
        print("\(display.uuid)  id=\(display.displayID)  \(display.name)  active=\(display.isActive)  builtin=\(display.isBuiltin)  brightness=\(brightness)  mode=\(mode)")
    }
}

func timed<T>(_ label: String, _ body: () throws -> T) rethrows -> T {
    let start = Date()
    defer { print(String(format: "  %@ took %.0f ms", label, Date().timeIntervalSince(start) * 1000)) }
    return try body()
}

switch arguments.first {
case "list":
    describe(backend.onlineDisplays())

case "modes":
    let display = find(arguments[1])
    for option in ModeCatalogue.options(from: backend.modes(of: display.displayID)) {
        print("\(option.label)\(option.isHiDPI ? " HiDPI" : "")  \(option.refreshRates.map(ModeCatalogue.refreshLabel).joined(separator: ", "))")
    }

case "brightness":
    let display = find(arguments[1])
    if arguments.count > 2, let value = Double(arguments[2]) {
        try timed("set") { try backend.setBrightness(value, of: display) }
    }
    let value = try timed("read") { try backend.brightness(of: display) }
    print("\(display.name): \(String(format: "%.1f%%", value * 100))")

case "blink":
    let display = find(arguments[1])
    let seconds = arguments.count > 2 ? Double(arguments[2]) ?? 5 : 5
    let id = display.displayID
    print("Disconnecting \(display.name) (id \(id)) for \(seconds)s…")
    try timed("disconnect") { try backend.setEnabled(false, displayID: id) }
    Thread.sleep(forTimeInterval: 1.5)
    print("While disconnected, CoreGraphics reports:")
    describe(backend.onlineDisplays())
    Thread.sleep(forTimeInterval: max(0, seconds - 1.5))
    print("Reconnecting…")
    try timed("reconnect") { try backend.setEnabled(true, displayID: id) }
    Thread.sleep(forTimeInterval: 3)
    print("After reconnect:")
    describe(backend.onlineDisplays())

default:
    print("usage: lumen-probe list | modes <uuid> | brightness <uuid> [value] | blink <uuid> <seconds>")
}
