/// One display mode: a size in points, the pixel buffer backing it, and a refresh rate.
public struct DisplayMode: Codable, Hashable, Sendable {
    public var width: Int
    public var height: Int
    public var pixelWidth: Int
    public var pixelHeight: Int
    public var refreshRate: Double

    public init(width: Int, height: Int, pixelWidth: Int, pixelHeight: Int, refreshRate: Double) {
        self.width = width
        self.height = height
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.refreshRate = refreshRate
    }

    /// Rendered at more pixels than points, i.e. a Retina ("HiDPI") mode.
    public var isHiDPI: Bool { pixelWidth > width }

    /// Same geometry and refresh rate, tolerating float noise in the rate (CoreGraphics
    /// reports 59.94 as 59.9400024).
    public func matches(_ other: DisplayMode) -> Bool {
        width == other.width && height == other.height
            && pixelWidth == other.pixelWidth && pixelHeight == other.pixelHeight
            && Self.refreshKey(refreshRate) == Self.refreshKey(other.refreshRate)
    }

    /// A refresh rate in hundredths of a hertz, for comparing and tagging rates without float
    /// noise.
    public static func refreshKey(_ rate: Double) -> Int { Int((rate * 100).rounded()) }
}
