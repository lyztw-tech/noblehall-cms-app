import Foundation
import SwiftData

@MainActor
enum TaskCreateOutbox {
    static var photosRoot: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return base.appending(path: "pending-task-photos", directoryHint: .isDirectory)
    }

    static func pendingCount(context: ModelContext) throws -> Int {
        try context.fetch(FetchDescriptor<PendingTaskCreateOutbox>()).count
    }

    /// 登出或重設本機資料：刪除佇列列與其暫存照片目錄。
    static func deleteAllPending(context: ModelContext) throws {
        for item in try context.fetch(FetchDescriptor<PendingTaskCreateOutbox>()) {
            let dir = photosRoot.appending(path: item.localId.uuidString, directoryHint: .isDirectory)
            try? FileManager.default.removeItem(at: dir)
            context.delete(item)
        }
    }

    /// 離線佇列列在「我的任務」等列表用（id 為 `pending-{uuid}`，勿當伺服器 taskId）。
    static func asListItem(_ row: PendingTaskCreateOutbox) -> QualityTaskListItemDto {
        QualityTaskListItemDto(
            id: "pending-\(row.localId.uuidString)",
            projectCode: row.projectCode,
            qualityDrawing: QualityDrawingRefDto(id: row.qualityDrawingId, name: row.drawingName),
            name: row.taskName,
            status: "in_progress",
            group: nil,
            room: nil,
            executor: nil
        )
    }

    /// 「指派給我」：僅個人執行且 executorId 為本人（與列表 API 語意一致）。
    static func pendingMatchesMineOnlyRow(_ row: PendingTaskCreateOutbox, userId: String?) -> Bool {
        guard let userId, !userId.isEmpty else { return false }
        guard let body = try? JSONDecoder().decode(CreateQualityTaskBody.self, from: row.bodyJSON) else { return false }
        if body.executorType == "user", let eid = body.executorId, eid == userId { return true }
        return false
    }

    static func enqueue(
        projectCode: String,
        qualityDrawingId: String,
        drawingName: String,
        body: CreateQualityTaskBody,
        photos: [(data: Data, filename: String)],
        context: ModelContext
    ) throws {
        let localId = UUID()
        let photoDir = photosRoot.appending(path: localId.uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: photoDir, withIntermediateDirectories: true)

        var relativePaths: [String] = []
        for (index, photo) in photos.enumerated() {
            let ext = (photo.filename as NSString).pathExtension.isEmpty ? "jpg" : (photo.filename as NSString).pathExtension
            let rel = "\(localId.uuidString)/\(index).\(ext)"
            let url = photosRoot.appending(path: rel)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try photo.data.write(to: url, options: .atomic)
            relativePaths.append(rel)
        }

        let bodyJSON = try JSONEncoder().encode(body)
        let photoPathsJSON = try JSONEncoder().encode(relativePaths)
        context.insert(
            PendingTaskCreateOutbox(
                localId: localId,
                projectCode: projectCode,
                qualityDrawingId: qualityDrawingId,
                drawingName: drawingName,
                taskName: body.name,
                bodyJSON: bodyJSON,
                photoPathsJSON: photoPathsJSON
            )
        )
        try context.save()
    }

    static func flushPending(context: ModelContext, spaceId: String, isOnline: Bool) async {
        guard isOnline else { return }
        let fetch = FetchDescriptor<PendingTaskCreateOutbox>(
            sortBy: [SortDescriptor(\.enqueuedAt, order: .forward)]
        )
        guard let items = try? context.fetch(fetch), !items.isEmpty else { return }

        for item in items {
            let localId = item.localId
            let projectCode = item.projectCode
            let qualityDrawingId = item.qualityDrawingId
            let body: CreateQualityTaskBody
            let relPaths: [String]
            do {
                body = try JSONDecoder().decode(CreateQualityTaskBody.self, from: item.bodyJSON)
                relPaths = try JSONDecoder().decode([String].self, from: item.photoPathsJSON)
            } catch {
                context.delete(item)
                try? context.save()
                continue
            }

            let created: CreateQualityTaskResponseDto
            do {
                created = try await QualityTaskAPI.createTask(
                    projectCode: projectCode,
                    qualityDrawingId: qualityDrawingId,
                    body: body,
                    spaceId: spaceId
                )
            } catch {
                return
            }

            // 先從佇列移除並存檔，再傳附件；避免另一輪 flush 在 await 期間再次送出同一筆。
            context.delete(item)
            do {
                try context.save()
            } catch {
                return
            }

            if !relPaths.isEmpty {
                var attachments: [(data: Data, filename: String, mimeType: String)] = []
                for (index, rel) in relPaths.enumerated() {
                    let url = photosRoot.appending(path: rel)
                    if let data = try? Data(contentsOf: url) {
                        attachments.append((data, "offline-\(index).jpg", "image/jpeg"))
                    }
                }
                if !attachments.isEmpty {
                    do {
                        try await QualityTaskAPI.uploadTaskAttachments(
                            projectCode: projectCode,
                            qualityDrawingId: qualityDrawingId,
                            taskId: created.id,
                            attachments: attachments,
                            spaceId: spaceId
                        )
                    } catch {
                        // 任務已建立；附件失敗不重送建立任務。
                    }
                }
            }
            let dir = photosRoot.appending(path: localId.uuidString, directoryHint: .isDirectory)
            try? FileManager.default.removeItem(at: dir)
        }
    }
}
