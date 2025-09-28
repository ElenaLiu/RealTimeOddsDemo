import Foundation
import Combine

final class StreamController {
    private let context: StreamContext

    init(
        configuration: OddsStreamTicker.Configuration,
        interval: TimeInterval,
        generator: @escaping @Sendable () -> OddsSnapshot?
    ) {
        context = StreamContext(
            configuration: configuration,
            interval: interval,
            generator: generator
        )
    }

    func start() -> AsyncStream<OddsSnapshot> {
        return AsyncStream { continuation in
            Task { [context] in await context.start(continuation: continuation) }
            
            continuation.onTermination = { [context] _ in
                Task.detached(priority: .medium) { await context.stop() }
            }
        }
    }

    func stop() {
        let context = context
        Task.detached(priority: .medium) { await context.stop() }
    }
    
    func getStatus() async -> StreamContext.Status {
        return await context.currentStatus
    }

    deinit {
        stop()
    }
}
