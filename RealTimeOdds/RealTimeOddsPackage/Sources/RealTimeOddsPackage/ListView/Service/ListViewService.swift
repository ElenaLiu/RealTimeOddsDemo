import Foundation
@preconcurrency import Combine

public final class ListViewService: @unchecked Sendable {
    // MARK: - Dependencies
    private let matchesAPI: MatchesMockAPI
    private let oddsAPI: OddsMockAPI
    private let oddsStream: OddsStreaming
    
    // MARK: - Configuration
    private let oddsUpdateInterval: TimeInterval
    private let oddsDeltaRange: ClosedRange<Double>
    
    // MARK: - State Management
    private let stateQueue = DispatchQueue(label: "com.realtimeodds.listviewservice.state", attributes: .concurrent)
    private var oddsSnapshotsStorage: [OddsSnapshot] = []
    
    private var oddsSnapshotsUnsafe: [OddsSnapshot] {
        get { stateQueue.sync { oddsSnapshotsStorage } }
        set { stateQueue.async(flags: .barrier) { self.oddsSnapshotsStorage = newValue } }
    }


    // MARK: - Initialization
    public init(
        matchesAPI: MatchesMockAPI = MatchesMockAPI(),
        oddsAPI: OddsMockAPI = OddsMockAPI(),
        oddsStream: OddsStreaming = OddsStreamTicker(),
        oddsUpdateInterval: TimeInterval = 0.1,
        oddsDeltaRange: ClosedRange<Double> = 0.4...2.4
    ) {
        self.matchesAPI = matchesAPI
        self.oddsAPI = oddsAPI
        self.oddsStream = oddsStream
        self.oddsUpdateInterval = oddsUpdateInterval
        self.oddsDeltaRange = oddsDeltaRange
        self.oddsSnapshotsStorage = []
    }

    // MARK: - Lifecycle
    deinit {
        stopOddsStream()
    }

    // MARK: - Public API
    public func loadMatches() async throws -> [Match] {
        let matches = try await matchesAPI.fetchMatches()
        return sortMatchesByStartTime(matches)
    }

    public func loadInitialOdds() async throws -> [OddsSnapshot] {
        let odds = try await oddsAPI.fetchInitialOdds()
        self.oddsSnapshotsUnsafe = odds
        return odds
    }

    public func oddsUpdatesStream() -> AsyncStream<OddsSnapshot> {
        return oddsStream.stream(interval: oddsUpdateInterval) {
            return self.generateOddsUpdate()
        }
    }

    public func oddsUpdatesPublisher() -> AnyPublisher<OddsSnapshot, Never> {
        let oddsSnapshots = self.oddsSnapshotsUnsafe
        
        
        let stream = oddsStream.stream(interval: oddsUpdateInterval) {
            guard !oddsSnapshots.isEmpty else { return nil }
            return self.generateOddsUpdate()
        }
        
        let subject = PassthroughSubject<OddsSnapshot, Never>()
        
        let task = Task { @Sendable in
            for await element in stream {
                if Task.isCancelled {
                    break
                }
                subject.send(element)
            }
            subject.send(completion: .finished)
        }
        
        return subject
            .handleEvents(receiveCancel: {
                task.cancel()
            })
            .eraseToAnyPublisher()
    }

    public func stopOddsStream() {
        oddsStream.stop()
    }
    
    public func getStreamStatus() async -> String {
        guard let status = await oddsStream.getStatus() else { return "Unknown" }
        switch status {
        case .idle: return "Idle"
        case .connecting: return "Connecting"
        case .connected: return "Connected"
        case .reconnecting: return "Reconnecting"
        case .stopped: return "Stopped"
        }
    }
    
    // MARK: - Private Methods
    private func sortMatchesByStartTime(_ matches: [Match]) -> [Match] {
        return matches.sorted { $0.startTime < $1.startTime }
    }
    
    private func generateOddsUpdate() -> OddsSnapshot? {
        guard !oddsSnapshotsUnsafe.isEmpty else { return nil }
        
        let randomIndex = Int.random(in: 0..<oddsSnapshotsUnsafe.count)
        let currentSnapshot = oddsSnapshotsUnsafe[randomIndex]
        let delta = randomDelta(in: oddsDeltaRange)
        
        // delta 是正數時，A 賠率漲、B 賠率跌；delta 是負數時，A 賠率跌、B 賠率漲。這樣就能保證兩邊總是反向走，一邊漲另一邊跌。
        let updatedSnapshot = OddsSnapshot(
            matchID: currentSnapshot.matchID,
            teamAOdds: (currentSnapshot.teamAOdds + delta).clampedOdds(decimals: 2),
            teamBOdds: (currentSnapshot.teamBOdds - delta).clampedOdds(decimals: 2),
            updatedAt: Date()
        )
        
        stateQueue.async(flags: .barrier) {
            self.oddsSnapshotsStorage[randomIndex] = updatedSnapshot
        }
        
        return updatedSnapshot
    }
    
    private func randomDelta(in range: ClosedRange<Double>) -> Double {
        let delta = Double.random(in: range)
        return Bool.random() ? delta : -delta
    }
}
