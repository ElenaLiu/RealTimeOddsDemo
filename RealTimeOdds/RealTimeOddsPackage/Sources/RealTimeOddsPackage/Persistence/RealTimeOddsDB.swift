import Foundation
import GRDB

// MARK: - Database Schema
public enum RealTimeOddsDB {
    // MARK: - Constants
    private enum Constants {
        static let migrationName = "createMatchOdds"
        static let startTimeIndexName = "matchOdds_startTime"
    }
    
    // MARK: - Migration
    public static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration(Constants.migrationName) { db in
            try CachedMatchOdds.create(on: db)
        }
        return migrator
    }
}

// MARK: - Database Model
    public struct CachedMatchOdds: Codable, FetchableRecord, PersistableRecord, Sendable {
    // MARK: - Constants
    static let schema = "matchOdds"
    private static let startTimeIndexName = "matchOdds_startTime"
    
    // MARK: - Column Definitions
    public enum Columns: String, CodingKey, ColumnExpression {
        case matchID
        case teamA
        case teamB
        case startTime
        case teamAOdds
        case teamBOdds
        case updatedAt

        public var name: String { rawValue }
    }

    // MARK: - Properties
    public let matchID: Int
    public let teamA: String
    public let teamB: String
    public let startTime: Date
    public let teamAOdds: Double?
    public let teamBOdds: Double?
    public let updatedAt: Date?

    // MARK: - Initialization
    public init(item: MatchOddsItem) {
        self.matchID = item.match.id
        self.teamA = item.match.teamA
        self.teamB = item.match.teamB
        self.startTime = item.match.startTime
        self.teamAOdds = item.odds?.teamAOdds
        self.teamBOdds = item.odds?.teamBOdds
        self.updatedAt = item.odds?.updatedAt
    }

    // MARK: - Conversion
    public func asMatchOddsItem() -> MatchOddsItem {
        let match = Match(matchID: matchID, teamA: teamA, teamB: teamB, startTime: startTime)
        let odds: OddsSnapshot?
        if let teamAOdds, let teamBOdds, let updatedAt {
            odds = OddsSnapshot(matchID: matchID, teamAOdds: teamAOdds, teamBOdds: teamBOdds, updatedAt: updatedAt)
        } else {
            odds = nil
        }
        return MatchOddsItem(match: match, odds: odds)
    }
}

// MARK: - Schema Definition
extension CachedMatchOdds {
    public static var databaseTableName: String { schema }

    public static func create(on database: Database) throws {
        try database.create(table: schema, ifNotExists: true) { table in
            table.column(Columns.matchID.name, .integer).primaryKey()
            table.column(Columns.teamA.name, .text).notNull()
            table.column(Columns.teamB.name, .text).notNull()
            table.column(Columns.startTime.name, .datetime).notNull()
            table.column(Columns.teamAOdds.name, .double)
            table.column(Columns.teamBOdds.name, .double)
            table.column(Columns.updatedAt.name, .datetime)
        }

        try database.create(index: startTimeIndexName, on: schema, columns: [Columns.startTime.name])
    }
}
