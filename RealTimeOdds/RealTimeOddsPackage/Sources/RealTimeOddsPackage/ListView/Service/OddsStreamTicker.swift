import Foundation

public protocol OddsStreaming: AnyObject {
    func stream(interval: TimeInterval, generator: @escaping @Sendable () -> OddsSnapshot?) -> AsyncStream<OddsSnapshot>
    func stop()
}

public final class OddsStreamTicker: OddsStreaming {
    private var timer: Timer?
    private var continuation: AsyncStream<OddsSnapshot>.Continuation?
    private var task: Task<Void, Never>?

    public init() {}

    public func stream(interval: TimeInterval, generator: @escaping @Sendable () -> OddsSnapshot?) -> AsyncStream<OddsSnapshot> {
        stop()

        return AsyncStream { continuation in
            self.continuation = continuation

            self.task = Task(priority: .utility) {
                while !Task.isCancelled {
                    if let snapshot = generator() {
                        continuation.yield(snapshot)
                    }

                    let ns = UInt64(max(0, interval) * 1_000_000_000)
                    try? await Task.sleep(nanoseconds: ns)
                }

                continuation.finish()
            }

            continuation.onTermination = { [weak self] _ in
                self?.stop()
            }
        }
    }

    public func stop() {
        timer?.invalidate()
        timer = nil

        task?.cancel()
        task = nil

        if let continuation = continuation {
            self.continuation = nil
            continuation.finish()
        }
    }
}

extension OddsStreamTicker: @unchecked Sendable {}
