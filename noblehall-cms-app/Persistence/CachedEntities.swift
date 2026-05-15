import Foundation
import SwiftData

@Model
final class CachedProject {
    @Attribute(.unique) var code: String
    var name: String
    var status: String
    var cachedAt: Date

    init(code: String, name: String, status: String, cachedAt: Date = Date()) {
        self.code = code
        self.name = name
        self.status = status
        self.cachedAt = cachedAt
    }
}

@Model
final class CachedTaskRow {
    @Attribute(.unique) var cacheKey: String
    var projectCode: String
    var taskId: String
    var drawingId: String?
    var drawingName: String?
    var title: String
    var status: String?
    var cachedAt: Date

    init(
        cacheKey: String,
        projectCode: String,
        taskId: String,
        drawingId: String?,
        drawingName: String?,
        title: String,
        status: String?,
        cachedAt: Date = Date()
    ) {
        self.cacheKey = cacheKey
        self.projectCode = projectCode
        self.taskId = taskId
        self.drawingId = drawingId
        self.drawingName = drawingName
        self.title = title
        self.status = status
        self.cachedAt = cachedAt
    }
}

@Model
final class CachedTaskDetailBlob {
    @Attribute(.unique) var cacheKey: String
    var projectCode: String
    var taskId: String
    var json: Data
    var cachedAt: Date

    init(projectCode: String, taskId: String, json: Data, cachedAt: Date = Date()) {
        self.cacheKey = "\(projectCode)|\(taskId)"
        self.projectCode = projectCode
        self.taskId = taskId
        self.json = json
        self.cachedAt = cachedAt
    }
}

@Model
final class CachedPlanAsset {
    @Attribute(.unique) var cacheKey: String
    var projectCode: String
    var qualityDrawingId: String
    var drawingName: String
    /// 相對於 App Caches/plan-assets 的檔名（例如 `專案碼/圖面uuid.dat`）。
    var imageRelativePath: String?
    var imageByteCount: Int64
    var pointsJSON: Data
    var pointCount: Int
    var markerReferenceWidth: Double
    var markerReferenceHeight: Double
    var cachedAt: Date

    init(
        cacheKey: String,
        projectCode: String,
        qualityDrawingId: String,
        drawingName: String,
        imageRelativePath: String?,
        imageByteCount: Int64,
        pointsJSON: Data,
        pointCount: Int,
        markerReferenceWidth: Double = 0,
        markerReferenceHeight: Double = 0,
        cachedAt: Date = Date()
    ) {
        self.cacheKey = cacheKey
        self.projectCode = projectCode
        self.qualityDrawingId = qualityDrawingId
        self.drawingName = drawingName
        self.imageRelativePath = imageRelativePath
        self.imageByteCount = imageByteCount
        self.pointsJSON = pointsJSON
        self.pointCount = pointCount
        self.markerReferenceWidth = markerReferenceWidth
        self.markerReferenceHeight = markerReferenceHeight
        self.cachedAt = cachedAt
    }
}

/// 新增任務表單：成員、群組、類別（離線填寫用）。
@Model
final class CachedAddTaskFormMeta {
    @Attribute(.unique) var projectCode: String
    var projectUUID: String
    var membersJSON: Data
    var groupsJSON: Data
    var categoriesJSON: Data
    var cachedAt: Date

    init(
        projectCode: String,
        projectUUID: String,
        membersJSON: Data,
        groupsJSON: Data,
        categoriesJSON: Data,
        cachedAt: Date = Date()
    ) {
        self.projectCode = projectCode
        self.projectUUID = projectUUID
        self.membersJSON = membersJSON
        self.groupsJSON = groupsJSON
        self.categoriesJSON = categoriesJSON
        self.cachedAt = cachedAt
    }
}

/// 離線建立任務佇列（連線後上傳）。
@Model
final class PendingTaskCreateOutbox {
    @Attribute(.unique) var localId: UUID
    var projectCode: String
    var qualityDrawingId: String
    var drawingName: String
    var taskName: String
    var bodyJSON: Data
    /// JSON 陣列：相對於 `TaskCreateOutbox.photosRoot` 的檔名。
    var photoPathsJSON: Data
    var enqueuedAt: Date

    init(
        localId: UUID = UUID(),
        projectCode: String,
        qualityDrawingId: String,
        drawingName: String,
        taskName: String,
        bodyJSON: Data,
        photoPathsJSON: Data,
        enqueuedAt: Date = Date()
    ) {
        self.localId = localId
        self.projectCode = projectCode
        self.qualityDrawingId = qualityDrawingId
        self.drawingName = drawingName
        self.taskName = taskName
        self.bodyJSON = bodyJSON
        self.photoPathsJSON = photoPathsJSON
        self.enqueuedAt = enqueuedAt
    }
}

@Model
final class PendingExecutionOutbox {
    @Attribute(.unique) var localId: UUID
    var projectCode: String
    var qualityDrawingId: String
    var qualityTaskId: String
    var executionReply: String
    /// JSON 陣列：相對於 `ExecutionOutbox.photosRoot` 的檔名。
    var photoPathsJSON: Data
    var enqueuedAt: Date

    init(
        localId: UUID = UUID(),
        projectCode: String,
        qualityDrawingId: String,
        qualityTaskId: String,
        executionReply: String,
        photoPathsJSON: Data = Data("[]".utf8),
        enqueuedAt: Date = Date()
    ) {
        self.localId = localId
        self.projectCode = projectCode
        self.qualityDrawingId = qualityDrawingId
        self.qualityTaskId = qualityTaskId
        self.executionReply = executionReply
        self.photoPathsJSON = photoPathsJSON
        self.enqueuedAt = enqueuedAt
    }
}
