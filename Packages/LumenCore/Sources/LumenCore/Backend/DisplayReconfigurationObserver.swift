import CoreGraphics

/// Display hot-plug and configuration changes as an async stream. One element is yielded per
/// completed change (the "about to change" callbacks are skipped). Changes arrive in bursts,
/// so consumers should debounce.
public enum DisplayReconfigurationObserver {
    public static func changes() -> AsyncStream<Void> {
        AsyncStream { continuation in
            let box = Unmanaged.passRetained(ContinuationBox(continuation))
            let token = UInt(bitPattern: box.toOpaque())

            CGDisplayRegisterReconfigurationCallback(callback, box.toOpaque())
            continuation.onTermination = { _ in
                guard let pointer = UnsafeMutableRawPointer(bitPattern: token) else { return }
                CGDisplayRemoveReconfigurationCallback(callback, pointer)
                Unmanaged<ContinuationBox>.fromOpaque(pointer).release()
            }
        }
    }

    private static let callback: CGDisplayReconfigurationCallBack = { _, flags, userInfo in
        guard !flags.contains(.beginConfigurationFlag), let userInfo else { return }
        Unmanaged<ContinuationBox>.fromOpaque(userInfo).takeUnretainedValue().continuation.yield()
    }

    private final class ContinuationBox: Sendable {
        let continuation: AsyncStream<Void>.Continuation
        init(_ continuation: AsyncStream<Void>.Continuation) { self.continuation = continuation }
    }
}
