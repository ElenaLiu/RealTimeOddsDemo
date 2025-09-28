# RealTimeOdds 架構說明

## Swift Concurrency

用 Swift Concurrency 來處理所有需要等待結果的非同步工作。

* **並行處理**：在 `ListViewViewModel.load()` 裡，用 `async let` 同時發起對比賽資訊 (matches) 和賠率 (odds) 的網路請求。這樣它們能並行執行，不用互相等待，提升了資料載入速度。

* **資料庫操作**：像 `hydrateFromCacheIfNeeded()` 這種耗時的 I/O 操作，將它包在一個 Task 裡，並使用 `await` 呼叫 GRDB，能確保這些工作在背景執行，不會卡住主執行緒。

* **即時串流**：用 `for await` 來處理 `AsyncStream<OddsSnapshot>` 傳來的資料。它讓處理即時資料流的邏輯變得簡潔明瞭。

## Combine

Combine 則是用來處理持續性的事件流和 UI 狀態綁定。

* **定時觸發器**：在 `OddsStreamTicker` 中，用 `Timer.publish().autoconnect().sink` 建立了一個簡單的定時器，定期觸發事件來推動 AsyncStream 產生資料。

* **UI 綁定**：讓 ViewController 訂閱 ViewModel 的 `$items`、`$isLoading` 等屬性。當 ViewModel 的狀態一有變動，UI 就會自動更新。避免了手動去呼叫 `reloadData`，讓 UI 程式碼保持乾淨。

## 執行緒安全

採取了多種策略來確保資料在多執行緒環境中存取安全。

* **@MainActor**：在 ViewModel 上標註了 `@MainActor`，強制所有與 UI 相關的狀態（如 items）只能在主執行緒上被讀寫，從根本上消除 Race Condition。

* **專屬佇列**：對於像 `ListViewService` 裡 `oddsSnapshots` 這種共享資料，使用了一個專屬的 `DispatchQueue` 來進行序列化存取。
    * **讀取 (get)**：用 `sync`，允許多個讀取並行 → 提升效能。
    * **寫入 (set)**：用 `async(flags: .barrier)`，確保「只有我能改，別人都要等我改完才能再讀/寫」。

* **GRDB DatabaseQueue**：GRDB 提供的 `DatabaseQueue` 已經內建了執行緒安全機制，直接利用它來確保所有資料庫操作按順序執行，避免資料不一致。

* **actor**：將 `StreamContext` 設為一個 `actor`，它能安全地管理串流狀態、心跳時間、重連次數等。即使有不同執行緒試圖更新這些資料，actor 也會保證同一時間只允許一個任務存取，確保了資料的完整性。

## UI 狀態更新

讓 ViewController 專注於顯示，ViewModel 負責管理狀態。

使用 `updateSnapshot(with:)` 這個 diffable snapshot 方法來高效更新 UITableView。它會自動計算新舊資料的差異，只更新需要變動的部分。

* 用 `OrderedDictionary` 來儲存資料，這保證了資料在記憶體中的順序與 UI 顯示的順序完全一致，簡化了資料處理邏輯。

* 當只有單一賠率有變動時，會精確地找到對應的 cell，只更新該賠率的 label 顏色，而不是整個 cell。

* 在 ViewModel 裡，每當 socket 連線狀態改變時（例如開始連線、連上伺服器、斷線或停止），就即時更新 `@Published var streamStatus`。Controller 透過 Combine 綁定這個屬性，所以右上角的狀態標籤會自動顯示最新的 socket 連線狀態。
