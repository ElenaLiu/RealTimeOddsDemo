import Foundation

public struct OddsMockAPI {
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

    public func fetchInitialOdds() async throws -> [OddsSnapshot] {
        try await Task.sleep(nanoseconds: 90_000_000)
        return try await Task.detached(priority: .high) {
            try Self.loadOdds()
        }.value
    }

    private static func loadOdds() throws -> [OddsSnapshot] {
        guard let url = Bundle.module.url(forResource: "odds", withExtension: "json") else {
            throw Error.missingResource
        }

        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            let dtos = try decoder.decode([OddsDTO].self, from: data)
            return dtos.map { OddsSnapshot(matchID: $0.matchID, teamAOdds: $0.teamAOdds, teamBOdds: $0.teamBOdds, updatedAt: Date()) }
        } catch {
            throw Error.decodingFailed(error)
        }
    }

    private struct OddsDTO: Decodable {
        let matchID: Int
        let teamAOdds: Double
        let teamBOdds: Double
    }
}
