import Testing
@testable import LumenCore

@Suite struct ModeCatalogueTests {
    static func mode(_ w: Int, _ h: Int, px pw: Int, _ ph: Int, _ hz: Double) -> DisplayMode {
        DisplayMode(width: w, height: h, pixelWidth: pw, pixelHeight: ph, refreshRate: hz)
    }

    // A real subset of the LS32D70xE's usable modes, with its duplicate 60 Hz entry.
    static let ls32: [DisplayMode] = [
        mode(1920, 1080, px: 3840, 2160, 60), mode(1920, 1080, px: 1920, 1080, 60),
        mode(1920, 1080, px: 1920, 1080, 50), mode(1920, 1080, px: 3840, 2160, 30),
        mode(1920, 1080, px: 1920, 1080, 30), mode(2560, 1440, px: 2560, 1440, 60),
        mode(2560, 1440, px: 5120, 2880, 60), mode(2560, 1440, px: 5120, 2880, 60),
        mode(2560, 1440, px: 2560, 1440, 30), mode(2560, 1440, px: 5120, 2880, 30),
    ]

    @Test func hiDPIMeansMorePixelsThanPoints() {
        #expect(Self.mode(2560, 1440, px: 5120, 2880, 60).isHiDPI)
        #expect(!Self.mode(2560, 1440, px: 2560, 1440, 60).isHiDPI)
    }

    @Test func groupsModesIntoResolutionOptionsOrderedLargestFirstHiDPIFirst() {
        let options = ModeCatalogue.options(from: Self.ls32)
        #expect(options.map(\.id) == ["2560x1440@2x", "2560x1440", "1920x1080@2x", "1920x1080"])
    }

    @Test func refreshRatesAreDescendingAndDeduplicated() {
        let options = ModeCatalogue.options(from: Self.ls32)
        #expect(options[0].refreshRates == [60, 30])
        #expect(options[3].refreshRates == [60, 50, 30])
    }

    @Test func nearlyEqualRefreshRatesStayDistinct() {
        let options = ModeCatalogue.options(from: [
            Self.mode(1920, 1080, px: 1920, 1080, 60), Self.mode(1920, 1080, px: 1920, 1080, 59.94),
        ])
        #expect(options[0].refreshRates == [60, 59.94])
    }

    @Test func picksLargestPixelBackingForAnOptionAndRate() {
        let modes = [Self.mode(1920, 1080, px: 2880, 1620, 60), Self.mode(1920, 1080, px: 3840, 2160, 60)]
        let option = ModeCatalogue.options(from: modes)[0]
        #expect(ModeCatalogue.mode(for: option, refreshRate: 60, in: modes) == Self.mode(1920, 1080, px: 3840, 2160, 60))
    }

    @Test func returnsNilForARateTheOptionDoesNotOffer() {
        let option = ModeCatalogue.options(from: Self.ls32)[0]
        #expect(ModeCatalogue.mode(for: option, refreshRate: 120, in: Self.ls32) == nil)
    }

    @Test func findsTheOptionContainingTheCurrentMode() {
        let options = ModeCatalogue.options(from: Self.ls32)
        let current = Self.mode(2560, 1440, px: 5120, 2880, 60)
        #expect(ModeCatalogue.option(containing: current, in: options)?.id == "2560x1440@2x")
    }

    @Test func keepsTheCurrentRefreshRateWhenSwitchingResolutionIfOffered() {
        let options = ModeCatalogue.options(from: Self.ls32)
        #expect(ModeCatalogue.preferredRefreshRate(for: options[3], current: 50) == 50)
        #expect(ModeCatalogue.preferredRefreshRate(for: options[0], current: 50) == 60)
        #expect(ModeCatalogue.preferredRefreshRate(for: options[0], current: nil) == 60)
    }

    @Test func modesMatchIgnoringRefreshRateRoundingNoise() {
        #expect(Self.mode(1920, 1080, px: 1920, 1080, 59.9400024).matches(Self.mode(1920, 1080, px: 1920, 1080, 59.94)))
        #expect(!Self.mode(1920, 1080, px: 1920, 1080, 60).matches(Self.mode(1920, 1080, px: 3840, 2160, 60)))
    }

    @Test func labels() {
        let option = ModeCatalogue.options(from: Self.ls32)[0]
        #expect(option.label == "2560 × 1440")
        #expect(ModeCatalogue.refreshLabel(120) == "120 Hz")
        #expect(ModeCatalogue.refreshLabel(59.94) == "59.94 Hz")
        #expect(ModeCatalogue.refreshLabel(0) == "Auto")
    }
}
