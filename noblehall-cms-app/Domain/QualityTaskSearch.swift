import Foundation

enum QualityTaskSearch {
    static func matches(_ task: QualityTaskListItemDto, query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return false }
        let fields: [String] = [
            task.name,
            task.room?.name,
            task.group?.name,
            task.qualityDrawing?.name,
            task.executor?.displayName,
            task.executor?.name,
            task.status.map { QualityTaskStatusLabels.displayName(for: $0) },
            task.createdAt.map { AppDateTimeFormat.fullDateTime($0) },
        ].compactMap { $0 } + (task.id.hasPrefix("pending-") ? ["尚未上傳", "離線新增"] : [])
        return fields.contains { $0.lowercased().contains(q) }
    }

    static func filter(_ tasks: [QualityTaskListItemDto], query: String) -> [QualityTaskListItemDto] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }
        return tasks
            .filter { matches($0, query: q) }
            .sorted { ($0.name ?? "") < ($1.name ?? "") }
    }
}
