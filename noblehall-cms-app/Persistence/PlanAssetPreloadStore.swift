import Foundation
import Observation

/// 平面圖／座標點預載進度（設定頁與啟動流程共用）。
@MainActor
@Observable
final class PlanAssetPreloadStore {
    static let shared = PlanAssetPreloadStore()

    private(set) var isRunning = false
    private(set) var lastError: String?
    private(set) var lastCompletedAt: Date?
    /// 例如 `3/12`
    private(set) var progressText: String?
    /// 上次預載成功寫入可離線顯示的圖檔數。
    private(set) var lastImagesCachedCount: Int = 0

    func begin(total: Int) {
        isRunning = true
        lastError = nil
        lastImagesCachedCount = 0
        progressText = total > 0 ? "0/\(total)" : nil
    }

    func noteImageCached() {
        lastImagesCachedCount += 1
    }

    func noteImagesCached(count: Int) {
        lastImagesCachedCount = count
    }

    func updateProgress(done: Int, total: Int) {
        progressText = "\(done)/\(total)"
    }

    func finish(error: String?) {
        isRunning = false
        lastError = error
        if error == nil {
            lastCompletedAt = Date()
        }
        progressText = nil
    }
}
