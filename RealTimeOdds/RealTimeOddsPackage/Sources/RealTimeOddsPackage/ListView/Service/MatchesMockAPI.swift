import Foundation

public struct MatchesMockAPI {
    public enum Error: Swift.Error {
        case missingResource
        case decodingFailed(Swift.Error)

        public var message: String {
            switch self {
            case .missingResource:
                return "資料遺失，請確認資源設定。"
            case .decodingFailed:
                return "資料解析失敗。"
            }
        }
    }

    public init() {}

    public func fetchMatches() async throws -> [Match] {
        try await Task.sleep(nanoseconds: 120_000_000)
        return try await Task.detached(priority: .high) {
            try Self.loadMatches()
        }.value
    }

    private static func loadMatches() throws -> [Match] {
        guard let url = Bundle.module.url(forResource: "matches", withExtension: "json") else {
            throw Error.missingResource
        }

        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let dtos = try decoder.decode([MatchDTO].self, from: data)
            return dtos.map { Match(matchID: $0.matchID, teamA: $0.teamA, teamB: $0.teamB, startTime: $0.startTime) }
        } catch {
            throw Error.decodingFailed(error)
        }
    }

    private struct MatchDTO: Decodable {
        let matchID: Int
        let teamA: String
        let teamB: String
        let startTime: Date
    }
}
