import Foundation
import GRDB

public actor GRDBListCache {
    // MARK: - Constants
    private enum Constants {
        static let cacheFolderName = "RealTimeOddsCache"
        static let databaseFileName = "list-cache.sqlite"
        static let migrationName = "createMatchOdds"
    }
    
    // MARK: - Configuration
    public struct Configuration: Sendable {
        public let databaseURL: URL

        public init(databaseURL: URL? = nil) throws {
            if let url = databaseURL {
                self.databaseURL = url
                return
            }
            
            self.databaseURL = try Self.createDefaultDatabaseURL()
        }
        
        private static func createDefaultDatabaseURL() throws -> URL {
            let fileManager = FileManager.default
            let supportDirectory = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )

            let folderURL = supportDirectory.appendingPathComponent(Constants.cacheFolderName, isDirectory: true)
            try fileManager.createDirectory(at: folderURL, withIntermediateDirectories: true, attributes: nil)
            return folderURL.appendingPathComponent(Constants.databaseFileName)
        }
    }

    // MARK: - Dependencies
    private let dbQueue: DatabaseQueue

    // MARK: - Initialization
    public init() throws {
        try self.init(configuration: try Configuration())
    }

    public init(configuration: Configuration) throws {
        dbQueue = try DatabaseQueue(path: configuration.databaseURL.path)
        try RealTimeOddsDB.migrator.migrate(dbQueue)
    }

    // MARK: - Public API
    public func loadItems() async throws -> [MatchOddsItem] {
        try await dbQueue.read { db in
            let records = try CachedMatchOdds.order(Column("startTime")).fetchAll(db)
            return records.map { $0.asMatchOddsItem() }
        }
    }

    public func replaceAll(with items: [MatchOddsItem]) async throws {
        try await dbQueue.write { db in
            try CachedMatchOdds.deleteAll(db)
            for item in items {
                try CachedMatchOdds(item: item).insert(db, onConflict: .replace)
            }
        }
    }

    public func saveItem(_ item: MatchOddsItem) async throws {
        try await dbQueue.write { db in
            try CachedMatchOdds(item: item).insert(db, onConflict: .replace)
        }
    }

    public func clear() async throws {
        _ = try await dbQueue.write { db in
            try CachedMatchOdds.deleteAll(db)
        }
    }
}
