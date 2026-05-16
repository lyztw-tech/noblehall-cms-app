import Foundation
import SwiftData

/// 離線／登出時的本機快取生命週期：避免下一個登入者看到前一帳號資料，並提供釋放磁碟空間的入口。
@MainActor
enum CacheMaintenance {
    /// 登出後呼叫：清除 SwiftData 內所有可重建快取、離線佇列與相關磁碟檔（Cookie 由 `SessionStore` 清除）。
    static func purgeAllLocalDataAfterLogout(modelContext: ModelContext) throws {
        try TaskCreateOutbox.deleteAllPending(context: modelContext)
        try ExecutionOutbox.deleteAllPending(context: modelContext)
        try deleteAllRows(CachedProject.self, context: modelContext)
        try deleteAllRows(CachedTaskRow.self, context: modelContext)
        try deleteAllRows(CachedTaskDetailBlob.self, context: modelContext)
        try PlanAssetCache.deleteAllRowsAndAssociatedDiskFiles(context: modelContext)
        try deleteAllRows(CachedAddTaskFormMeta.self, context: modelContext)
        PlanAssetCache.deleteEntireDiskCacheDirectory()
        try modelContext.save()
    }

    /// 保留登入狀態，只移除此專案的離線暫存（任務列表快取、詳情 JSON、平面圖、新增任務表單快取）。
    static func purgeOfflineDataForProject(projectCode: String, modelContext: ModelContext) throws {
        let pc = projectCode
        try modelContext.fetch(FetchDescriptor<CachedTaskRow>(predicate: #Predicate { $0.projectCode == pc }))
            .forEach { modelContext.delete($0) }
        try modelContext.fetch(FetchDescriptor<CachedTaskDetailBlob>(predicate: #Predicate { $0.projectCode == pc }))
            .forEach { modelContext.delete($0) }
        try PlanAssetCache.deleteAllRowsAndDiskFiles(forProjectCode: pc, context: modelContext)
        try modelContext.fetch(FetchDescriptor<CachedAddTaskFormMeta>(predicate: #Predicate { $0.projectCode == pc }))
            .forEach { modelContext.delete($0) }
        try modelContext.save()
    }

    private static func deleteAllRows<T: PersistentModel>(_ type: T.Type, context: ModelContext) throws {
        try context.fetch(FetchDescriptor<T>()).forEach { context.delete($0) }
    }

    /// 裝置可用儲存空間（Caches 所在磁區）。
    static func deviceAvailableStorageBytes() -> Int64? {
        let home = (NSHomeDirectory() as NSString).expandingTildeInPath
        guard let attrs = try? FileManager.default.attributesOfFileSystem(forPath: home) else { return nil }
        return attrs[.systemFreeSize] as? Int64
    }

    /// 此專案離線暫存總占用（平面圖、任務詳情、表單快取、待上傳照片等）。
    static func projectOfflineUsedBytes(projectCode: String, context: ModelContext) throws -> Int64 {
        var total = (try? PlanAssetCache.stats(projectCode: projectCode, context: context))?.totalBytes ?? 0
        let pc = projectCode
        let details = try context.fetch(
            FetchDescriptor<CachedTaskDetailBlob>(predicate: #Predicate { $0.projectCode == pc })
        )
        total += details.reduce(Int64(0)) { $0 + Int64($1.json.count) }
        let forms = try context.fetch(
            FetchDescriptor<CachedAddTaskFormMeta>(predicate: #Predicate { $0.projectCode == pc })
        )
        for form in forms {
            total += Int64(form.membersJSON.count + form.groupsJSON.count + form.categoriesJSON.count)
        }
        let pendingTasks = try context.fetch(
            FetchDescriptor<PendingTaskCreateOutbox>(predicate: #Predicate { $0.projectCode == pc })
        )
        for row in pendingTasks {
            let dir = TaskCreateOutbox.photosRoot.appending(path: row.localId.uuidString, directoryHint: .isDirectory)
            total += directorySize(at: dir)
        }
        let pendingExecs = try context.fetch(
            FetchDescriptor<PendingExecutionOutbox>(predicate: #Predicate { $0.projectCode == pc })
        )
        for row in pendingExecs {
            let dir = ExecutionOutbox.photosRoot.appending(path: row.localId.uuidString, directoryHint: .isDirectory)
            total += directorySize(at: dir)
        }
        return total
    }

    private static func directorySize(at url: URL) -> Int64 {
        guard FileManager.default.fileExists(atPath: url.path) else { return 0 }
        guard let enumerator = FileManager.default.enumerator(
            at: url,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            total += Int64(size)
        }
        return total
    }
}
