import Foundation

public struct Match: Identifiable, Equatable, Hashable, Sendable {
    public let id: Int
    public let teamA: String
    public let teamB: String
    public let startTime: Date

    public init(matchID: Int, teamA: String, teamB: String, startTime: Date) {
        self.id = matchID
        self.teamA = teamA
        self.teamB = teamB
        self.startTime = startTime
    }
}

// UI
public struct MatchOddsItem: Identifiable, Hashable, Sendable {
    public var id: Int { match.id }
    public let match: Match
    public let odds: OddsSnapshot?

    public init(match: Match, odds: OddsSnapshot?) {
        self.match = match
        self.odds = odds
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(match.id)
    }

    public static func == (lhs: MatchOddsItem, rhs: MatchOddsItem) -> Bool {
        lhs.match.id == rhs.match.id
    }
}
