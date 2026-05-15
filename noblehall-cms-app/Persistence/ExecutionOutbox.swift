import Foundation
import SwiftData

@MainActor
enum ExecutionOutbox {
    static var photosRoot: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return base.appending(path: "pending-execution-photos", directoryHint: .isDirectory)
    }

    static func pendingCount(context: ModelContext) throws -> Int {
        try context.fetch(FetchDescriptor<PendingExecutionOutbox>()).count
    }

    static func pendingForTask(
        projectCode: String,
        taskId: String,
        context: ModelContext
    ) throws -> [PendingExecutionOutbox] {
        let pc = projectCode
        let tid = taskId
        return try context.fetch(
            FetchDescriptor<PendingExecutionOutbox>(
                predicate: #Predicate<PendingExecutionOutbox> { $0.projectCode == pc && $0.qualityTaskId == tid },
                sortBy: [SortDescriptor(\.enqueuedAt, order: .forward)]
            )
        )
    }

    /// 登出或重設本機資料：刪除佇列列與其暫存照片目錄。
    static func deleteAllPending(context: ModelContext) throws {
        for item in try context.fetch(FetchDescriptor<PendingExecutionOutbox>()) {
            deletePhotos(for: item)
            context.delete(item)
        }
    }

    static func enqueue(
        projectCode: String,
        qualityDrawingId: String,
        taskId: String,
        executionReply: String,
        photos: [(data: Data, filename: String, mimeType: String)],
        context: ModelContext
    ) throws {
        let localId = UUID()
        var relativePaths: [String] = []
        for (index, photo) in photos.enumerated() {
            let ext = (photo.filename as NSString).pathExtension.isEmpty ? "jpg" : (photo.filename as NSString).pathExtension
            let rel = "\(localId.uuidString)/\(index).\(ext)"
            let url = photosRoot.appending(path: rel)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try photo.data.write(to: url, options: .atomic)
            relativePaths.append(rel)
        }

        let photoPathsJSON = try JSONEncoder().encode(relativePaths)
        context.insert(
            PendingExecutionOutbox(
                localId: localId,
                projectCode: projectCode,
                qualityDrawingId: qualityDrawingId,
                qualityTaskId: taskId,
                executionReply: executionReply,
                photoPathsJSON: photoPathsJSON
            )
        )
        try context.save()
    }

    static func photoCount(for item: PendingExecutionOutbox) -> Int {
        (try? JSONDecoder().decode([String].self, from: item.photoPathsJSON))?.count ?? 0
    }

    static func flushPending(context: ModelContext, spaceId: String, isOnline: Bool) async {
        guard isOnline else { return }
        let fetch = FetchDescriptor<PendingExecutionOutbox>(
            sortBy: [SortDescriptor(\.enqueuedAt, order: .forward)]
        )
        guard let items = try? context.fetch(fetch), !items.isEmpty else { return }

        for item in items {
            do {
                let relPaths = (try? JSONDecoder().decode([String].self, from: item.photoPathsJSON)) ?? []
                var attachments: [(data: Data, filename: String, mimeType: String)] = []
                for (index, rel) in relPaths.enumerated() {
                    let url = photosRoot.appending(path: rel)
                    guard let data = try? Data(contentsOf: url) else { continue }
                    let ext = (rel as NSString).pathExtension.lowercased()
                    let mime = ext == "png" ? "image/png" : "image/jpeg"
                    attachments.append((data, "offline-\(index).\(ext.isEmpty ? "jpg" : ext)", mime))
                }
                _ = try await QualityTaskAPI.createExecution(
                    projectCode: item.projectCode,
                    qualityDrawingId: item.qualityDrawingId,
                    taskId: item.qualityTaskId,
                    executionReply: item.executionReply.isEmpty ? nil : item.executionReply,
                    attachments: attachments,
                    spaceId: spaceId
                )
                deletePhotos(for: item)
                context.delete(item)
                try context.save()
            } catch {
                return
            }
        }
    }

    private static func deletePhotos(for item: PendingExecutionOutbox) {
        let dir = photosRoot.appending(path: item.localId.uuidString, directoryHint: .isDirectory)
        try? FileManager.default.removeItem(at: dir)
    }
}
