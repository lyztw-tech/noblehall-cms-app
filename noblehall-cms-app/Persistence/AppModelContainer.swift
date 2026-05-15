import SwiftData
import SwiftUI

enum AppModelContainer {
    /// 新增／修改 `@Model` 時遞增；快取資料可重建，不寫 migration plan。
    private static let schemaVersion = 3

    static let shared: ModelContainer = {
        do {
            return try makeContainer()
        } catch {
            fatalError("SwiftData 初始化失敗：\(error)")
        }
    }()

    private static var storeURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appending(path: "noblehall-cache-v\(schemaVersion).store", directoryHint: .notDirectory)
    }

    private static func makeContainer() throws -> ModelContainer {
        let schema = Schema([
            CachedProject.self,
            CachedTaskRow.self,
            CachedTaskDetailBlob.self,
            CachedPlanAsset.self,
            CachedAddTaskFormMeta.self,
            PendingTaskCreateOutbox.self,
            PendingExecutionOutbox.self,
        ])
        let config = ModelConfiguration(schema: schema, url: storeURL)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            removeStoreFiles(at: storeURL)
            return try ModelContainer(for: schema, configurations: [config])
        }
    }

    private static func removeStoreFiles(at url: URL) {
        let fm = FileManager.default
        let candidates = [
            url,
            URL(fileURLWithPath: url.path + "-wal"),
            URL(fileURLWithPath: url.path + "-shm"),
        ]
        for file in candidates where fm.fileExists(atPath: file.path) {
            try? fm.removeItem(at: file)
        }
    }
}
