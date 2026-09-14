import Testing
@testable import LumenCore

actor AppliedValues {
    private(set) var values: [(uuid: String, value: Double)] = []
    func record(_ uuid: String, _ value: Double) { values.append((uuid, value)) }
}

@Suite struct BrightnessCoalescerTests {
    @Test func rapidChangesCollapseToTheLatestValue() async {
        let applied = AppliedValues()
        let coalescer = BrightnessCoalescer { uuid, value in
            await applied.record(uuid, value)
            try? await Task.sleep(for: .milliseconds(30))
        }
        for step in 1...10 {
            await coalescer.submit(uuid: "LS32", value: Double(step) / 10)
        }
        await coalescer.waitUntilIdle()

        let values = await applied.values.map(\.value)
        #expect(values.last == 1.0)
        #expect(values.count <= 2)
    }

    @Test func eachDisplayDrainsIndependently() async {
        let applied = AppliedValues()
        let coalescer = BrightnessCoalescer { uuid, value in await applied.record(uuid, value) }
        await coalescer.submit(uuid: "LS32", value: 0.3)
        await coalescer.submit(uuid: "G81", value: 0.7)
        await coalescer.waitUntilIdle()

        let values = await applied.values
        #expect(values.contains { $0.uuid == "LS32" && $0.value == 0.3 })
        #expect(values.contains { $0.uuid == "G81" && $0.value == 0.7 })
    }

    @Test func aValueSubmittedAfterIdleIsStillApplied() async {
        let applied = AppliedValues()
        let coalescer = BrightnessCoalescer { uuid, value in await applied.record(uuid, value) }
        await coalescer.submit(uuid: "LS32", value: 0.2)
        await coalescer.waitUntilIdle()
        await coalescer.submit(uuid: "LS32", value: 0.9)
        await coalescer.waitUntilIdle()

        #expect(await applied.values.map(\.value) == [0.2, 0.9])
    }
}
