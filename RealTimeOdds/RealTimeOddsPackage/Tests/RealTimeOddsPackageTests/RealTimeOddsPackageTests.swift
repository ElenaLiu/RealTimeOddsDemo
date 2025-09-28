import XCTest
import Combine
@testable import RealTimeOddsPackage

final class RealTimeOddsPackageTests: XCTestCase {
    private var cancellables: Set<AnyCancellable>!
    
    override func setUp() {
        super.setUp()
        cancellables = Set<AnyCancellable>()
    }
    
    override func tearDown() {
        cancellables = nil
        super.tearDown()
    }
    
    // MARK: - 功能 1: 資料載入測試
    
    @MainActor
    func testListViewViewModelDataLoading() async {
        let viewModel = ListViewViewModel(service: ListViewService(), cache: nil)

        let expectation = XCTestExpectation(description: "Data loaded successfully")
        
        viewModel.$items
            .dropFirst()
            .sink { items in
                XCTAssertGreaterThan(items.count, 0)
                expectation.fulfill()
            }
            .store(in: &cancellables)
        
        viewModel.load()

        await fulfillment(of: [expectation], timeout: 5.0)
        XCTAssertFalse(viewModel.isLoading)
    }
    
    // MARK: - 功能 2: 即時賠率流測試
    
    func testOddsStreamTickerBasicFunctionality() async {
        let ticker = OddsStreamTicker()
        let expectedOdds = OddsSnapshot(matchID: 1, teamAOdds: 1.5, teamBOdds: 2.5, updatedAt: Date())
        
        let stream = ticker.stream(interval: 0.1) {
            return expectedOdds
        }
        
        let expectation = XCTestExpectation(description: "Receive odds from stream")
        
        actor OddsStorage {
            private var storedOdds: OddsSnapshot?
            
            func store(_ odds: OddsSnapshot) {
                storedOdds = odds
            }
            
            func getOdds() -> OddsSnapshot? {
                return storedOdds
            }
        }
        
        let storage = OddsStorage()
        
        Task {
            for await odds in stream {
                await storage.store(odds)
                expectation.fulfill()
                break
            }
        }
        
        await fulfillment(of: [expectation], timeout: 1.0)
        let generatedOdds = await storage.getOdds()
        XCTAssertNotNil(generatedOdds)
        XCTAssertEqual(generatedOdds?.matchID, expectedOdds.matchID)
        
        ticker.stop()
    }
    
    // MARK: - 功能 3: 服務層測試
    
    func testListViewServiceDataLoading() async throws {
        
        let service = ListViewService()
        
        let matches = try await service.loadMatches()
        let odds = try await service.loadInitialOdds()
        
        XCTAssertGreaterThan(matches.count, 0)
        XCTAssertGreaterThan(odds.count, 0)
    }
    
    // MARK: - 功能 4: 資料模型測試
    
    func testMatchOddsItemModel() {
        let match = Match(matchID: 1, teamA: "Team A", teamB: "Team B", startTime: Date())
        let odds = OddsSnapshot(matchID: 1, teamAOdds: 1.5, teamBOdds: 2.5, updatedAt: Date())
        
        let item = MatchOddsItem(match: match, odds: odds)
        
        XCTAssertEqual(item.id, 1)
        XCTAssertEqual(item.match.teamA, "Team A")
        XCTAssertEqual(item.odds?.teamAOdds, 1.5)
    }
    
    // MARK: - 功能 5: 性能測試
    
    func testOddsStreamTickerPerformance() async {
        let config = OddsStreamTicker.Configuration(
            handshakeDelay: 0.0, // 無連線延遲
            heartbeatInterval: 0, // 無心跳
            heartbeatTimeout: 0,
            reconnectDelay: 0,
            reconnectJitterRange: 0...0,
            heartbeatFailureProbability: 0, // 無隨機斷線
            spontaneousDropProbability: 0, // 無隨機掉線
            maxReconnectDelay: 0,
            maxUpdatesPerSecond: 100 // 提高速率限制
        )
        let ticker = OddsStreamTicker(configuration: config)
        let expectedOdds = OddsSnapshot(matchID: 1, teamAOdds: 1.5, teamBOdds: 2.5, updatedAt: Date())
        let maxUpdates = 3
        
        let stream = ticker.stream(interval: 0.05) { // 更快的間隔
            return expectedOdds
        }
        
        let expectation = XCTestExpectation(description: "Performance test")
        expectation.expectedFulfillmentCount = maxUpdates
        
        actor Counter {
            private var count = 0
            
            func increment() -> Int {
                count += 1
                return count
            }
            
            func getCount() -> Int {
                return count
            }
        }
        
        let counter = Counter()
        
        Task {
            for await _ in stream {
                let currentCount = await counter.increment()
                expectation.fulfill()
                if currentCount >= maxUpdates {
                    break
                }
            }
        }
 
        await fulfillment(of: [expectation], timeout: 2.0) // 減少超時時間
        let finalCount = await counter.getCount()
        XCTAssertEqual(finalCount, maxUpdates)
        
        ticker.stop()
    }
}
