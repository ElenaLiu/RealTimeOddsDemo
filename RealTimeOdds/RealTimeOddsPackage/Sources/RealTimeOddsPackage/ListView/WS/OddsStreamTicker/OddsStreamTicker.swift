import Foundation
import Combine

public protocol OddsStreaming: AnyObject {
    func stream(interval: TimeInterval, generator: @escaping @Sendable () -> OddsSnapshot?) -> AsyncStream<OddsSnapshot>
    func stop()
    func getStatus() async -> StreamContext.Status?
}

public final class OddsStreamTicker: OddsStreaming {
    public struct Configuration: Sendable {
        public let handshakeDelay: TimeInterval // 模擬 實際網路環境 初始連線延遲
        public let heartbeatInterval: TimeInterval // 心跳間隔
        public let heartbeatTimeout: TimeInterval // 心跳超時時間
        public let reconnectDelay: TimeInterval // 重連延遲
        public let reconnectJitterRange: ClosedRange<Double> // 重連延遲的隨機抖動範圍
        public let heartbeatFailureProbability: Double // 模擬隨機斷線
        public let spontaneousDropProbability: Double // 隨機斷線的機率
        public let maxReconnectDelay: TimeInterval // 重連等待的最長時間
        public let maxUpdatesPerSecond: Int //每秒最多推送多少更新

        public static let `default` = Configuration(
            handshakeDelay: 0.35,
            heartbeatInterval: 5,
            heartbeatTimeout: 30,
            reconnectDelay: 1.5,
            reconnectJitterRange: 0...1.2,
            heartbeatFailureProbability: 0.01,
            spontaneousDropProbability: 0.03,
            maxReconnectDelay: 6,
            maxUpdatesPerSecond: 10
        )

        public init(
            handshakeDelay: TimeInterval,
            heartbeatInterval: TimeInterval,
            heartbeatTimeout: TimeInterval,
            reconnectDelay: TimeInterval,
            reconnectJitterRange: ClosedRange<Double>,
            heartbeatFailureProbability: Double,
            spontaneousDropProbability: Double,
            maxReconnectDelay: TimeInterval,
            maxUpdatesPerSecond: Int
        ) {
            self.handshakeDelay = handshakeDelay
            self.heartbeatInterval = heartbeatInterval
            self.heartbeatTimeout = heartbeatTimeout
            self.reconnectDelay = reconnectDelay
            self.reconnectJitterRange = reconnectJitterRange
            self.heartbeatFailureProbability = heartbeatFailureProbability
            self.spontaneousDropProbability = spontaneousDropProbability
            self.maxReconnectDelay = maxReconnectDelay
            self.maxUpdatesPerSecond = maxUpdatesPerSecond
        }
    }

    private let configuration: Configuration
    private var controller: StreamController?

    public init(configuration: Configuration = .default) {
        self.configuration = configuration
    }

    public func stream(interval: TimeInterval, generator: @escaping @Sendable () -> OddsSnapshot?) -> AsyncStream<OddsSnapshot> {
        stop()
        let controller = StreamController(
            configuration: configuration,
            interval: interval,
            generator: generator
        )
        self.controller = controller
        return controller.start()
    }

    public func stop() {
        controller?.stop()
        controller = nil
    }
    
    public func getStatus() async -> StreamContext.Status? {
        return await controller?.getStatus()
    }
}

extension OddsStreamTicker: @unchecked Sendable {}
