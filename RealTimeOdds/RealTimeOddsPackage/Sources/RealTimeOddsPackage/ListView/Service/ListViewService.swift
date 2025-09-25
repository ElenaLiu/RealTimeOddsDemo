import Foundation

public final class ListViewService {
    private let matchesAPI: MatchesProviding
    private let oddsAPI: OddsProviding
    private let oddsStream: OddsStreaming
    private let oddsUpdateInterval: TimeInterval
    private let oddsDeltaRange: ClosedRange<Double>

    private let stateQueue = DispatchQueue(label: "com.realtimeodds.listviewservice.state")
    private var oddsSnapshots: [OddsSnapshot]

    public init(
        matchesAPI: MatchesProviding = MatchesMockAPI(),
        oddsAPI: OddsProviding = OddsMockAPI(),
        oddsStream: OddsStreaming = OddsStreamTicker(),
        oddsUpdateInterval: TimeInterval = 1.5,
        oddsDeltaRange: ClosedRange<Double> = 0.3...4.0
    ) {
        self.matchesAPI = matchesAPI
        self.oddsAPI = oddsAPI
        self.oddsStream = oddsStream
        self.oddsUpdateInterval = oddsUpdateInterval
        self.oddsDeltaRange = oddsDeltaRange
        self.oddsSnapshots = []
    }

    deinit {
        stopOddsStream()
    }

    public func loadMatches() async throws -> [Match] {
        let matches = try await matchesAPI.fetchMatches()
        return matches.sorted { $0.startTime < $1.startTime }
    }

    public func loadInitialOdds() async throws -> [OddsSnapshot] {
        let odds = try await oddsAPI.fetchInitialOdds()
        stateQueue.sync { self.oddsSnapshots = odds }
        return odds
    }

    public func oddsUpdatesStream() -> AsyncStream<OddsSnapshot> {
        oddsStream.stream(interval: oddsUpdateInterval) { [weak self] in
            self?.makeOddsUpdate()
        }
    }

    public func stopOddsStream() {
        oddsStream.stop()
    }

    private func makeOddsUpdate() -> OddsSnapshot? {
        stateQueue.sync {
            guard !oddsSnapshots.isEmpty else { return nil }
            let index = Int.random(in: 0..<oddsSnapshots.count)
            let current = oddsSnapshots[index]
            let delta = Double.random(in: oddsDeltaRange)
            let signedDelta = Bool.random() ? delta : -delta

            let updated = OddsSnapshot(
                matchID: current.matchID,
                teamAOdds: clampOdds(current.teamAOdds + signedDelta),
                teamBOdds: clampOdds(current.teamBOdds - signedDelta),
                updatedAt: Date()
            )

            oddsSnapshots[index] = updated
            return updated
        }
    }

    private func clampOdds(_ value: Double) -> Double {
        let rounded = (value * 100).rounded() / 100
        let lowerBound = 1.10
        let upperBound = 4.50
        return min(max(rounded, lowerBound), upperBound)
    }
}

extension ListViewService: @unchecked Sendable {}
