/// Collapses a burst of slider changes (brightness or contrast) into as few hardware writes as
/// possible. Each display drains on its own: it applies a value, and if newer values arrived
/// meanwhile it applies only the latest of them.
///
/// DDC writes take tens of milliseconds, so sending every slider tick would lag far behind the
/// user's finger.
public actor AdjustmentCoalescer {
    public typealias Apply = @Sendable (_ uuid: String, _ value: Double) async -> Void

    private let apply: Apply
    private var pending: [String: Double] = [:]
    private var drains: [String: Task<Void, Never>] = [:]

    public init(apply: @escaping Apply) {
        self.apply = apply
    }

    public func submit(uuid: String, value: Double) {
        pending[uuid] = value
        guard drains[uuid] == nil else { return }
        drains[uuid] = Task { await drain(uuid) }
    }

    /// Returns once every submitted value has been applied.
    public func waitUntilIdle() async {
        while let next = drains.values.first {
            await next.value
        }
    }

    private func drain(_ uuid: String) async {
        while let value = pending.removeValue(forKey: uuid) {
            await apply(uuid, value)
        }
        drains[uuid] = nil
    }
}
