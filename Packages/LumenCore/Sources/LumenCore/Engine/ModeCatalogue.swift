/// A resolution the user can pick: a size in points, HiDPI or not, and the refresh rates
/// available at that size.
public struct ResolutionOption: Hashable, Sendable, Identifiable {
    public let width: Int
    public let height: Int
    public let isHiDPI: Bool
    /// Descending, de-duplicated.
    public let refreshRates: [Double]

    public var id: String { "\(width)x\(height)\(isHiDPI ? "@2x" : "")" }
    public var label: String { "\(width) × \(height)" }
}

/// Turns the long, duplicate-heavy mode list CoreGraphics returns (150 usable modes on the
/// G81SF) into a short list of resolution options.
public enum ModeCatalogue {
    public static func options(from modes: [DisplayMode]) -> [ResolutionOption] {
        let groups = Dictionary(grouping: modes) { GroupKey(width: $0.width, height: $0.height, isHiDPI: $0.isHiDPI) }
        return groups
            .map { key, modes in
                var seen = Set<Int>()
                let rates = modes.map(\.refreshRate)
                    .sorted(by: >)
                    .filter { seen.insert(DisplayMode.refreshKey($0)).inserted }
                return ResolutionOption(width: key.width, height: key.height, isHiDPI: key.isHiDPI, refreshRates: rates)
            }
            .sorted { lhs, rhs in
                if lhs.width != rhs.width { return lhs.width > rhs.width }
                if lhs.height != rhs.height { return lhs.height > rhs.height }
                return lhs.isHiDPI && !rhs.isHiDPI
            }
    }

    /// The concrete mode for an option and rate. When several modes qualify, the one with the
    /// largest pixel backing wins, since it renders sharpest.
    public static func mode(for option: ResolutionOption, refreshRate: Double, in modes: [DisplayMode]) -> DisplayMode? {
        modes
            .filter {
                $0.width == option.width && $0.height == option.height && $0.isHiDPI == option.isHiDPI
                    && DisplayMode.refreshKey($0.refreshRate) == DisplayMode.refreshKey(refreshRate)
            }
            .max { $0.pixelWidth * $0.pixelHeight < $1.pixelWidth * $1.pixelHeight }
    }

    public static func option(containing mode: DisplayMode, in options: [ResolutionOption]) -> ResolutionOption? {
        options.first { $0.width == mode.width && $0.height == mode.height && $0.isHiDPI == mode.isHiDPI }
    }

    /// Keeps the current rate when the new resolution offers it, otherwise the fastest.
    public static func preferredRefreshRate(for option: ResolutionOption, current: Double?) -> Double? {
        if let current, option.refreshRates.contains(where: { DisplayMode.refreshKey($0) == DisplayMode.refreshKey(current) }) {
            return current
        }
        return option.refreshRates.first
    }

    /// The resolutions worth offering in a menu, like the list System Settings shows before
    /// "Show all resolutions":
    /// - a standard size is hidden when its HiDPI twin offers every refresh rate it does, so the
    ///   G81SF's 240 Hz standard modes stay available;
    /// - anything narrower than 1024 points is hidden;
    /// - the option containing `current` is always kept.
    public static func essentialOptions(from options: [ResolutionOption], keeping current: DisplayMode?) -> [ResolutionOption] {
        let hiDPIRates = Dictionary(
            options.filter(\.isHiDPI).map { ("\($0.width)x\($0.height)", Set($0.refreshRates.map(DisplayMode.refreshKey))) },
            uniquingKeysWith: { first, _ in first }
        )
        let kept = current.flatMap { option(containing: $0, in: options) }?.id

        return options.filter { option in
            if option.id == kept { return true }
            guard option.width >= 1024 else { return false }
            guard !option.isHiDPI, let twin = hiDPIRates["\(option.width)x\(option.height)"] else { return true }
            return !Set(option.refreshRates.map(DisplayMode.refreshKey)).isSubset(of: twin)
        }
    }

    /// "2560 × 1440 HiDPI · 120 Hz"
    public static func summary(_ mode: DisplayMode) -> String {
        "\(mode.width) × \(mode.height)\(mode.isHiDPI ? " HiDPI" : "") · \(refreshLabel(mode.refreshRate))"
    }

    public static func refreshLabel(_ rate: Double) -> String {
        guard rate > 0 else { return "Auto" }
        let hundredths = DisplayMode.refreshKey(rate)
        let whole = hundredths / 100
        let fraction = hundredths % 100
        if fraction == 0 { return "\(whole) Hz" }
        let digits = fraction % 10 == 0 ? "\(fraction / 10)" : (fraction < 10 ? "0\(fraction)" : "\(fraction)")
        return "\(whole).\(digits) Hz"
    }

    private struct GroupKey: Hashable {
        let width: Int
        let height: Int
        let isHiDPI: Bool
    }
}
