import Foundation

@MainActor
public final class ListViewViewModel: ObservableObject {
    @Published public private(set) var items: [MatchOddsItem] = []
    @Published public private(set) var isLoading = false
    @Published public private(set) var errorMessage: String?

    private let service: ListViewService
    private var oddsByMatchID: [Int: OddsSnapshot] = [:]
    private var loadTask: Task<Void, Never>?
    private var updatesTask: Task<Void, Never>?

    public init(service: ListViewService = ListViewService()) {
        self.service = service
    }

    public func load() {
        cancelOngoingWorkLocked()
        setLoadingState(isLoading: true, errorMessage: nil)

        let service = self.service
        loadTask = Task(priority: .userInitiated) { [weak self] in

            do {
                async let matchesTask = service.loadMatches()
                async let oddsTask = service.loadInitialOdds()
                let (matches, odds) = try await (matchesTask, oddsTask)

                try Task.checkCancellation()
                await MainActor.run {
                    guard let viewModel = self else { return }
                    viewModel.applyInitialState(matches: matches, odds: odds)
                    viewModel.startStreamingLocked()
                }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    guard let viewModel = self else { return }
                    viewModel.handleLoadErrorLocked(error)
                }
            }

            await MainActor.run {
                guard let viewModel = self else { return }
                viewModel.loadTask = nil
            }
        }
    }

    public func stop() {
        cancelOngoingWorkLocked()
        setLoadingState(isLoading: false, errorMessage: nil)
    }

    private func startStreamingLocked() {
        let stream = service.oddsUpdatesStream()
        updatesTask = Task(priority: .utility) { [weak self] in

            for await snapshot in stream {
                guard !Task.isCancelled else { break }
                await MainActor.run {
                    guard let viewModel = self else { return }
                    viewModel.handleOddsUpdateLocked(snapshot)
                }
            }

            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let viewModel = self else { return }
                viewModel.handleStreamCompletionLocked()
            }

            await MainActor.run {
                guard let viewModel = self else { return }
                viewModel.updatesTask = nil
            }
        }
    }

    private func handleOddsUpdateLocked(_ snapshot: OddsSnapshot) {
        oddsByMatchID[snapshot.matchID] = snapshot
        items = items.map { item in
            guard item.match.id == snapshot.matchID else { return item }
            return MatchOddsItem(match: item.match, odds: snapshot)
        }
    }

    private func applyInitialState(matches: [Match], odds: [OddsSnapshot]) {
        oddsByMatchID = Dictionary(uniqueKeysWithValues: odds.map { ($0.matchID, $0) })
        items = matches.map { MatchOddsItem(match: $0, odds: oddsByMatchID[$0.id]) }
        isLoading = false
        errorMessage = nil
    }

    private func handleStreamCompletionLocked() {
        guard errorMessage == nil, !items.isEmpty else { return }
        errorMessage = "賠率更新暫時中斷，請下拉重新整理。"
    }

    private func handleLoadErrorLocked(_ error: Swift.Error) {
        items = []
        oddsByMatchID.removeAll()
        setLoadingState(isLoading: false, errorMessage: Self.errorMessage(for: error))
    }

    private func cancelOngoingWorkLocked() {
        loadTask?.cancel()
        loadTask = nil
        updatesTask?.cancel()
        updatesTask = nil
        service.stopOddsStream()
    }

    private func setLoadingState(isLoading: Bool, errorMessage: String?) {
        self.isLoading = isLoading
        self.errorMessage = errorMessage
    }

    private static func errorMessage(for error: Swift.Error) -> String {
        if error is MatchesMockAPI.Error { return "資料載入失敗，請稍後再試。" }
        if error is OddsMockAPI.Error { return "資料載入失敗，請稍後再試。" }

        if let urlError = error as? URLError {
            return "網路連線異常 (\(urlError.code.rawValue))，請稍後再試。"
        }

        if error is DecodingError {
            return "資料解析失敗，請稍後再試。"
        }

        return "發生未預期錯誤，請稍後再試。"
    }
}
