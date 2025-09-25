import Foundation

public struct OddsSnapshot: Equatable, Hashable, Sendable {
    public let matchID: Int
    public let teamAOdds: Double
    public let teamBOdds: Double
    public let updatedAt: Date

    public init(matchID: Int, teamAOdds: Double, teamBOdds: Double, updatedAt: Date) {
        self.matchID = matchID
        self.teamAOdds = teamAOdds
        self.teamBOdds = teamBOdds
        self.updatedAt = updatedAt
    }
}
