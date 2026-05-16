import Foundation
import SwiftData

@MainActor
enum LocalTaskCache {
    static func replaceProjectTasks(_ items: [QualityTaskListItemDto], projectCode: String, context: ModelContext) throws {
        let pc = projectCode
        let toDelete = try context.fetch(
            FetchDescriptor<CachedTaskRow>(predicate: #Predicate<CachedTaskRow> { $0.projectCode == pc })
        )
        for row in toDelete {
            context.delete(row)
        }
        for item in items {
            let key = "\(projectCode)|\(item.id)"
            context.insert(
                CachedTaskRow(
                    cacheKey: key,
                    projectCode: projectCode,
                    taskId: item.id,
                    drawingId: item.qualityDrawing?.id,
                    drawingName: item.qualityDrawing?.name,
                    title: item.name ?? "未命名任務",
                    status: item.status,
                    createdAt: item.createdAt
                )
            )
        }
    }

    static func tasks(projectCode: String, context: ModelContext) throws -> [CachedTaskRow] {
        let pc = projectCode
        return try context.fetch(
            FetchDescriptor<CachedTaskRow>(
                predicate: #Predicate<CachedTaskRow> { $0.projectCode == pc },
                sortBy: [SortDescriptor(\.title)]
            )
        )
    }

    static func upsertProjects(_ items: [ProjectListItemDto], context: ModelContext) throws {
        let all = try context.fetch(FetchDescriptor<CachedProject>())
        for p in items {
            let code = p.code
            if let row = all.first(where: { $0.code == code }) {
                row.name = p.name
                row.status = p.status
                row.cachedAt = Date()
            } else {
                context.insert(CachedProject(code: p.code, name: p.name, status: p.status))
            }
        }
    }

    static func cachedProjects(context: ModelContext) throws -> [CachedProject] {
        try context.fetch(FetchDescriptor<CachedProject>()).sorted { $0.name < $1.name }
    }

    static func saveDetailJSON(projectCode: String, taskId: String, data: Data, context: ModelContext) throws {
        let key = "\(projectCode)|\(taskId)"
        let k = key
        let row = try context.fetch(
            FetchDescriptor<CachedTaskDetailBlob>(predicate: #Predicate<CachedTaskDetailBlob> { $0.cacheKey == k })
        ).first
        if let row {
            row.json = data
            row.cachedAt = Date()
        } else {
            context.insert(CachedTaskDetailBlob(projectCode: projectCode, taskId: taskId, json: data))
        }
    }

    static func saveDetail(_ dto: QualityTaskDetailResponseDto, projectCode: String, taskId: String, context: ModelContext) throws {
        let data = try JSONEncoder.api.encode(dto)
        try saveDetailJSON(projectCode: projectCode, taskId: taskId, data: data, context: context)
    }

    static func loadDetail(projectCode: String, taskId: String, context: ModelContext) throws -> QualityTaskDetailResponseDto? {
        let pc = projectCode
        let tid = taskId
        guard let row = try context.fetch(
            FetchDescriptor<CachedTaskDetailBlob>(
                predicate: #Predicate<CachedTaskDetailBlob> { $0.projectCode == pc && $0.taskId == tid }
            )
        ).first else { return nil }
        return try JSONDecoder.api.decode(QualityTaskDetailResponseDto.self, from: row.json)
    }
}

private extension JSONDecoder {
    static var api: JSONDecoder {
        let d = JSONDecoder()
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        d.dateDecodingStrategy = .custom { dec in
            let c = try dec.singleValueContainer()
            let s = try c.decode(String.self)
            if let date = withFraction.date(from: s) { return date }
            if let date = plain.date(from: s) { return date }
            throw DecodingError.dataCorruptedError(in: c, debugDescription: s)
        }
        return d
    }
}

private extension JSONEncoder {
    static var api: JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }
}
