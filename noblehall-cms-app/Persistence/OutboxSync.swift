import Foundation
import SwiftData

@MainActor
enum OutboxSync {
    /// 多處同時呼叫 flush 時，若在 `await` API 期間重入，會重複送出同一筆離線佇列。
    /// 以「單一執行中 + 等待佇列」序列化，避免使用巢狀 `Task` 讀取 `.value` 觸發 Swift 6 隔離警告。
    private static var flushRunning = false
    private static var flushWaiters: [CheckedContinuation<Void, Never>] = []

    static func flushPending(modelContext: ModelContext, isOnline: Bool) async {
        guard isOnline else { return }
        while flushRunning {
            await withCheckedContinuation { flushWaiters.append($0) }
        }
        flushRunning = true
        defer {
            flushRunning = false
            if !flushWaiters.isEmpty {
                let next = flushWaiters.removeFirst()
                next.resume()
            }
        }
        await TaskCreateOutbox.flushPending(context: modelContext, isOnline: true)
        await ExecutionOutbox.flushPending(context: modelContext, isOnline: true)
    }
}
