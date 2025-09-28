import Foundation
import Combine

public actor StreamContext {
    public enum Status: Sendable {
        case idle
        case connecting
        case connected
        case reconnecting
        case stopped
    }

    private let configuration: OddsStreamTicker.Configuration
    private let interval: TimeInterval
    private let generator: @Sendable () -> OddsSnapshot?

    private var continuation: AsyncStream<OddsSnapshot>.Continuation?
    private var status: Status = .idle
    
    public var currentStatus: Status {
        status
    }
    private var lastHeartbeat: Date = .now
    private var reconnectAttempts = 0
    private var emissionWindowStart: Date = .now
    private var emissionCount = 0
    private var lastEmission: Date = .distantPast
    private var timerCancellable: AnyCancellable?

    private var heartbeatTask: Task<Void, Never>?
    private var watchdogTask: Task<Void, Never>?
    private var reconnectTask: (id: UUID, task: Task<Void, Never>)?

    private var lastPing: Date = .distantPast
    private var lastPong: Date = .distantPast

    init(
        configuration: OddsStreamTicker.Configuration,
        interval: TimeInterval,
        generator: @escaping @Sendable () -> OddsSnapshot?
    ) {
        self.configuration = configuration
        self.interval = interval
        self.generator = generator
    }

    func start(continuation: AsyncStream<OddsSnapshot>.Continuation) {
        self.continuation = continuation
        status = .idle
        lastHeartbeat = Date()
        reconnectAttempts = 0 // 把 重連次數 歸零。
        emissionWindowStart = Date() // 設定一個新的 發送起點時間
        emissionCount = 0 // 把目前已經發送的筆數歸零
        lastEmission = .distantPast // 最後一次發送時間 設成一個超級久以前的值，保證連線剛建立好時，可以馬上送出第一筆資料

        launchLoopsIfNeeded()
        scheduleInitialConnection()
    }

    func stop() {
        guard status != .stopped else { return }
        status = .stopped
        cancelTasks()
        continuation?.finish()
        continuation = nil
    }

    // MARK: - 連線相關
    private func scheduleInitialConnection() {
        reconnectTask?.task.cancel()
        let attemptID = UUID()
        let task = Task { [weak self] in
            guard let self else { return }
            await self.connect(delay: 0, attemptID: attemptID)
        }
        reconnectTask = (attemptID, task)
    }

    private func scheduleReconnect() {
        reconnectTask?.task.cancel()
        let delay = nextReconnectDelay()
        let attemptID = UUID()
        let task = Task { [weak self] in
            guard let self else { return }
            await self.connect(delay: delay, attemptID: attemptID)
        }
        reconnectTask = (attemptID, task)
    }

    private func connect(delay: TimeInterval, attemptID: UUID) async {
        defer { clearReconnectTaskIfNeeded(attemptID) }

        if delay > 0 {
            await sleep(for: delay)
            guard status != .stopped else { return }
        }

        guard status != .stopped else { return }

        status = .connecting

        await sleep(for: configuration.handshakeDelay)
        guard status != .stopped else { return }

        status = .connected
        lastPing = Date()
        lastPong = Date()
        lastHeartbeat = Date()
        reconnectAttempts = 0
        emissionWindowStart = Date()
        emissionCount = 0
        lastEmission = Date()
    }

    private func clearReconnectTaskIfNeeded(_ attemptID: UUID) {
        guard reconnectTask?.id == attemptID else { return }
        reconnectTask = nil
    }
    
    // 計算下一次重連要等多久，次數越多，delay 越長
    private func nextReconnectDelay() -> TimeInterval {
        reconnectAttempts += 1
        let base = configuration.reconnectDelay * Double(reconnectAttempts)
        let jitter = Double.random(in: configuration.reconnectJitterRange)
        return min(configuration.maxReconnectDelay, base + jitter)
    }

    // MARK: - 傳資料相關
    /// 定時送出賠率更新 (tick loop)」，讓外部 AsyncStream 能持續收到模擬的賠率資料
    private func startUpdateTimer() {
        guard timerCancellable == nil else { return }
        let cadence = 1.0 / Double(max(configuration.maxUpdatesPerSecond, 1))
        let publisher = Timer.publish(
            every: cadence,
            tolerance: cadence * 0.2,
            on: .main,
            in: .common
        ).autoconnect()
        timerCancellable = publisher.sink { [weak self] _ in
            self?.enqueueTick()
        }
    }

    private func stopUpdateTimer() {
        timerCancellable?.cancel()
        timerCancellable = nil
    }

    nonisolated func enqueueTick() {
        Task { await self.tick() }
    }

    func tick() {
        guard status == .connected else { return }
        guard continuation != nil else { return }

        let now = Date()
        let minimumInterval = max(interval, 0)
        if now.timeIntervalSince(lastEmission) < minimumInterval {
            return
        }

        guard canEmit(now: now) else { return }

        guard let snapshot = generator() else { return }
        print("[OddsStreamTicker] emit matchID=\(snapshot.matchID) A=\(snapshot.teamAOdds) B=\(snapshot.teamBOdds)")
        continuation?.yield(snapshot)
        lastHeartbeat = now
        lastEmission = now
        emissionCount += 1

        if shouldDropConnection() {
            triggerReconnect()
        }
    }

    private func canEmit(now: Date) -> Bool {
        let limit = configuration.maxUpdatesPerSecond
        guard limit > 0 else { return true }

        let elapsed = now.timeIntervalSince(emissionWindowStart)
        if elapsed >= 1 {
            emissionWindowStart = now
            emissionCount = 0
            return true
        }

        return emissionCount < limit
    }

    // MARK: - 心跳相關
    private func heartbeatLoop() async {
        let heartbeatInterval = configuration.heartbeatInterval
        guard heartbeatInterval > 0 else { return }

        while status != .stopped {
            await sleep(for: heartbeatInterval)
            if status == .stopped { return }
            guard status == .connected else { continue }

            lastPing = Date()
            print("[Heartbeat] >>> ping")

            if shouldDropHeartbeat() {
                print("[Heartbeat] !!! pong lost")
                continue
            }

            lastPong = Date()
            lastHeartbeat = Date()
            print("[Heartbeat] <<< pong")
        }
    }

    private func shouldDropHeartbeat() -> Bool {
        guard configuration.heartbeatFailureProbability > 0 else { return false }
        return Double.random(in: 0...1) < configuration.heartbeatFailureProbability
    }

    // MARK: - 掉線相關
    private func watchdogLoop() async {
        while status != .stopped {
            await sleep(for: 0.25)
            if status == .stopped { return }
            guard status == .connected else { continue }

            guard lastPong != .distantPast else { continue }

            // 如果 太久沒收到 pong，就判斷連線掛掉 → 觸發重連
            let elapsed = Date().timeIntervalSince(lastPong)
            if elapsed > configuration.heartbeatTimeout {
                triggerReconnect()
            }
        }
    }

    private func shouldDropConnection() -> Bool {
        guard configuration.spontaneousDropProbability > 0 else { return false }
        return Double.random(in: 0...1) < configuration.spontaneousDropProbability
    }

    // MARK: - 重連相關
    private func triggerReconnect() {
        guard status == .connected else { return }
        status = .reconnecting
        scheduleReconnect()
    }

    // MARK: - 輔助方法
    private func launchLoopsIfNeeded() {
        startUpdateTimer()

        if heartbeatTask == nil {
            heartbeatTask = Task { [weak self] in
                guard let self else { return }
                await self.heartbeatLoop()
            }
        }

        if watchdogTask == nil {
            watchdogTask = Task { [weak self] in
                guard let self else { return }
                await self.watchdogLoop()
            }
        }
    }

    private func cancelTasks() {
        heartbeatTask?.cancel()
        watchdogTask?.cancel()
        reconnectTask?.task.cancel()
        stopUpdateTimer()

        heartbeatTask = nil
        watchdogTask = nil
        reconnectTask = nil
    }

    private func sleep(for seconds: TimeInterval) async {
        if seconds <= 0 {
            await Task.yield()
            return
        }

        do {
            try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
        } catch {
            // 忽略取消錯誤
        }
    }
}
