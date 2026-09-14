/// A display's live values at the moment "Save current as preset" is pressed.
public struct CapturedDisplay: Sendable {
    public var display: KnownDisplay
    public var brightness: Double?
    public var mode: DisplayMode?

    public init(display: KnownDisplay, brightness: Double?, mode: DisplayMode?) {
        self.display = display
        self.brightness = brightness
        self.mode = mode
    }
}

public enum PresetFactory {
    public static let nightBrightness = 0.10

    /// Night and Day, built from the displays attached on first launch. Modes are left out so
    /// the seeds never change a resolution by surprise.
    public static func seedPresets(from displays: [KnownDisplay], builtinBrightness: Double?) -> [Preset] {
        let attached = displays.filter { $0.status != .unavailable }
        let controlOptionCommand = HotkeyModifiers.control | HotkeyModifiers.option | HotkeyModifiers.command

        let night = Preset(
            name: "Night", symbol: "moon.stars",
            hotkey: Hotkey(keyCode: 45, modifiers: controlOptionCommand, keyLabel: "N"),
            displays: attached.map {
                $0.info.isBuiltin
                    ? DisplayTarget(uuid: $0.id, name: $0.info.name, connected: true, brightness: nightBrightness)
                    : DisplayTarget(uuid: $0.id, name: $0.info.name, connected: false)
            }
        )
        let day = Preset(
            name: "Day", symbol: "sun.max",
            hotkey: Hotkey(keyCode: 2, modifiers: controlOptionCommand, keyLabel: "D"),
            displays: attached.map {
                DisplayTarget(uuid: $0.id, name: $0.info.name, connected: true,
                              brightness: $0.info.isBuiltin ? builtinBrightness : nil)
            }
        )
        return [night, day]
    }

    public static func capture(name: String, symbol: String, displays: [CapturedDisplay]) -> Preset {
        Preset(
            name: name, symbol: symbol,
            displays: displays.compactMap { captured in
                let info = captured.display.info
                switch captured.display.status {
                case .online:
                    return DisplayTarget(uuid: info.uuid, name: info.name, connected: true,
                                         brightness: captured.brightness, mode: captured.mode)
                case .disconnected:
                    return DisplayTarget(uuid: info.uuid, name: info.name, connected: false)
                case .unavailable:
                    return nil
                }
            }
        )
    }

    /// "Update from Current Setup": replaces the targets for every display captured now and
    /// keeps targets for displays that are not attached at the moment, so updating Day while
    /// undocked does not drop the monitors. Newly attached displays are appended.
    public static func updating(_ preset: Preset, from displays: [CapturedDisplay]) -> Preset {
        let fresh = capture(name: preset.name, symbol: preset.symbol, displays: displays).displays
        let freshByID = Dictionary(fresh.map { ($0.uuid, $0) }, uniquingKeysWith: { first, _ in first })
        var updated = preset
        updated.displays = preset.displays.map { freshByID[$0.uuid] ?? $0 }
            + fresh.filter { target in !preset.displays.contains { $0.uuid == target.uuid } }
        return updated
    }

    /// `base`, or `base 2`, `base 3`… when that name is taken.
    public static func uniqueName(_ base: String, existing: [String]) -> String {
        let taken = Set(existing)
        guard taken.contains(base) else { return base }
        return (2...).lazy.map { "\(base) \($0)" }.first { !taken.contains($0) }!
    }
}
