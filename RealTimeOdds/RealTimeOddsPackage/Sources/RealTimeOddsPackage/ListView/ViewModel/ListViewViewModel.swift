import Foundation
import Combine
import OrderedCollections

@MainActor
public final class ListViewViewModel: ObservableObject {
    // MARK: - Published Properties
    @Published public private(set) var items: [MatchOddsItem] = []
    @Published public private(set) var isLoading = false
    @Published public private(set) var errorMessage: String?
    @Published public private(set) var updatedItem: MatchOddsItem?
    @Published public private(set) var streamStatus: String = "Unknown"

    // MARK: - Dependencies
    private let service: ListViewService
    private let cache: GRDBListCache?
    
    // MARK: - State Management
    private var oddsByMatchID: [Int: OddsSnapshot] = [:]
    private var itemsStore = OrderedDictionary<Int, MatchOddsItem>()
    private var hasLoadedInitialData = false
    
    // MARK: - Task Management
    private var loadTask: Task<Void, Never>?
    private var updatesCancellable: AnyCancellable?
    private var statusUpdateTask: Task<Void, Never>?

    // MARK: - Initialization
    public init(
        service: ListViewService = ListViewService(),
        cache: GRDBListCache? = try? GRDBListCache()
    ) {
        self.service = service
        self.cache = cache
    }

    // MARK: - Public API
    public func load() {
        // 如果已經載入過資料且緩存中有資料，只啟動即時賠率更新的串流，不重新載入整份比賽清單。
        if hasLoadedInitialData && !itemsStore.isEmpty {
            startOddsStreaming()
            return
        }
        
        cancelOngoingWork()
        setLoadingState(isLoading: true, errorMessage: nil)
        hydrateFromCacheIfNeeded()
        startDataLoading()
    }

    public func stop() {
        cancelOngoingWork()
        setLoadingState(isLoading: false, errorMessage: nil)
        updatedItem = nil
    }
    
    public func refresh() {
        // 強制重新載入，忽略緩存狀態
        hasLoadedInitialData = false
        load()
    }

    // MARK: - Data Loading
    private func startDataLoading() {
        let service = self.service
        loadTask = Task(priority: .high) { [weak self] in
            do {
                let (matches, odds) = try await self?.loadMatchesAndOdds(from: service) ?? ([], [])
                try Task.checkCancellation()
                
                await MainActor.run {
                    guard let viewModel = self else { return }
                    viewModel.applyInitialState(matches: matches, odds: odds)
                    viewModel.startOddsStreaming()
                }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard let viewModel = self else { return }
                    viewModel.handleLoadError(error)
                }
            }
            
            await MainActor.run {
                guard let viewModel = self else { return }
                viewModel.loadTask = nil
            }
        }
    }
    
    private func loadMatchesAndOdds(from service: ListViewService) async throws -> ([Match], [OddsSnapshot]) {
        async let matchesTask = service.loadMatches()
        async let oddsTask = service.loadInitialOdds()
        return try await (matchesTask, oddsTask)
    }
    
    private func startOddsStreaming() {
        updatesCancellable?.cancel()

        let publisher = service.oddsUpdatesPublisher()
            .receive(on: DispatchQueue.main)

        updatesCancellable = publisher.sink(
            receiveCompletion: { [weak self] _ in
                guard let self else { return }
                self.handleStreamCompletion()
                self.updatesCancellable = nil
            },
            receiveValue: { [weak self] snapshot in
                guard let self else { return }
                self.handleOddsUpdate(snapshot)
            }
        )
        
        startStatusMonitoring()
    }

    // MARK: - Odds Updates
    private func handleOddsUpdate(_ snapshot: OddsSnapshot) {
        oddsByMatchID[snapshot.matchID] = snapshot
        
        guard let currentItem = itemsStore[snapshot.matchID] else { return }
        
        let updatedItem = MatchOddsItem(match: currentItem.match, odds: snapshot)
        updateItemInStore(updatedItem)
        persistItem(updatedItem)
    }
    
    private func updateItemInStore(_ item: MatchOddsItem) {
        itemsStore[item.id] = item
        items = Array(itemsStore.values)
        updatedItem = item
    }

    // MARK: - State Management
    private func applyInitialState(matches: [Match], odds: [OddsSnapshot]) {
        updateOddsMapping(odds)
        buildItemsStore(from: matches)
        updatePublishedState()
        persistSnapshot(items)
    }
    
    private func updateOddsMapping(_ odds: [OddsSnapshot]) {
        oddsByMatchID = odds.toDictionary(by: \.matchID)
    }
    
    private func buildItemsStore(from matches: [Match]) {
        itemsStore.removeAll()
        for match in matches {
            let item = MatchOddsItem(match: match, odds: oddsByMatchID[match.id])
            itemsStore[match.id] = item
        }
    }
    
    private func updatePublishedState() {
        items = Array(itemsStore.values)
        updatedItem = nil
        isLoading = false
        errorMessage = nil
        hasLoadedInitialData = true
    }

    private func handleStreamCompletion() {
        // Stream 完成是正常行為（如重新載入時），不需要顯示錯誤訊息
        // 只有在真正的中斷情況下才需要處理
    }

    private func handleLoadError(_ error: Swift.Error) {
        clearAllData()
        setLoadingState(isLoading: false, errorMessage: Self.errorMessage(for: error))
    }
    
    private static func errorMessage(for error: Swift.Error) -> String {
        if error is MatchesMockAPI.Error { return "比賽資料載入失敗，請稍後再試。" }
        if error is OddsMockAPI.Error { return "賠率資料載入失敗，請稍後再試。" }
        
        return "發生未知錯誤，請稍後再試。"
    }
    
    private func clearAllData() {
        itemsStore.removeAll()
        items = []
        oddsByMatchID.removeAll()
        updatedItem = nil
    }
    
    // MARK: - Cache Management
    // Catch 裡的舊資料放進 ViewModel，讓畫面立刻有內容
    private func hydrateFromCacheIfNeeded() {
        guard itemsStore.isEmpty, let cache else { return }
        
        Task { [weak self, cache] in
            do {
                let cachedItems = try await cache.loadItems()
                guard !cachedItems.isEmpty else { return }
                
                await MainActor.run {
                    guard let viewModel = self else { return }
                    viewModel.applyCachedItems(cachedItems)
                }
            } catch {
                // 快取載入失敗不影響主要流程，靜默處理
            }
        }
    }

    // Catch 依起始時間排序、放入 itemsStore 與 items
    private func applyCachedItems(_ cachedItems: [MatchOddsItem]) {
        guard itemsStore.isEmpty else { return }
        
        let sortedItems = cachedItems.sorted(by: { $0.match.startTime < $1.match.startTime })
        for item in sortedItems {
            itemsStore[item.id] = item
        }
        
        items = Array(itemsStore.values)
        updatedItem = nil
        hasLoadedInitialData = true
    }

    private func persistSnapshot(_ snapshot: [MatchOddsItem]) {
        guard let cache else { return }
        
        Task { [cache] in
            do {
                try await cache.replaceAll(with: snapshot)
            } catch {
                // Catch 失敗不影響主要流程，靜默處理
            }
        }
    }

    private func persistItem(_ item: MatchOddsItem) {
        guard let cache else { return }
        
        Task { [cache] in
            do {
                try await cache.saveItem(item)
            } catch {
                // Catch 失敗不影響主要流程，靜默處理
            }
        }
    }

    // MARK: - Task Management
    private func cancelOngoingWork() {
        cancelLoadTask()
        cancelUpdatesTask()
        cancelStatusUpdateTask()
        service.stopOddsStream()
    }
    
    private func cancelLoadTask() {
        loadTask?.cancel()
        loadTask = nil
    }
    
    private func cancelUpdatesTask() {
        updatesCancellable?.cancel()
        updatesCancellable = nil
    }
    
    private func cancelStatusUpdateTask() {
        statusUpdateTask?.cancel()
        statusUpdateTask = nil
    }
    
    private func startStatusMonitoring() {
        statusUpdateTask?.cancel()
        
        statusUpdateTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self = self else { return }
                
                let status = await service.getStreamStatus()
                await MainActor.run {
                    self.streamStatus = status
                }
                
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5秒更新一次
            }
        }
    }
    
    private func setLoadingState(isLoading: Bool, errorMessage: String?) {
        self.isLoading = isLoading
        self.errorMessage = errorMessage
    }

}
