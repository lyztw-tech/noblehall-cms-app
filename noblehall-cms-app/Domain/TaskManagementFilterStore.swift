import Foundation
import Observation

struct TaskManagementFilterOption: Identifiable, Hashable, Sendable {
    let id: String
    let label: String
}

/// 任務管理進階篩選（對齊 Web 任務管理總表 `advancedFilter`）。
@Observable
final class TaskManagementFilterStore {
    var revision = 0

    var qualityDrawingId: String?
    var statuses: [String] = []
    var search: String = ""
    var groupIds: [String] = []
    var roomIds: [String] = []
    var categoryIds: [String] = []
    var priorities: [String] = []
    var executorIds: [String] = []
    var reviewerIds: [String] = []
    var createdFrom: Date?
    var createdTo: Date?
    var dueFrom: Date?
    var dueTo: Date?

    var activeConditionCount: Int {
        var count = 0
        if qualityDrawingId != nil { count += 1 }
        if !statuses.isEmpty { count += 1 }
        if !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { count += 1 }
        if !groupIds.isEmpty { count += 1 }
        if !roomIds.isEmpty { count += 1 }
        if !categoryIds.isEmpty { count += 1 }
        if !priorities.isEmpty { count += 1 }
        if createdFrom != nil || createdTo != nil { count += 1 }
        if dueFrom != nil || dueTo != nil { count += 1 }
        if !executorIds.isEmpty { count += 1 }
        if !reviewerIds.isEmpty { count += 1 }
        return count
    }

    func reset() {
        qualityDrawingId = nil
        statuses = []
        search = ""
        groupIds = []
        roomIds = []
        categoryIds = []
        priorities = []
        executorIds = []
        reviewerIds = []
        createdFrom = nil
        createdTo = nil
        dueFrom = nil
        dueTo = nil
        bump()
    }

    func bump() {
        revision += 1
    }

    func displaySummary(
        field: TaskManagementFilterField,
        drawings: [QualityDrawingListItemDto],
        members: [ProjectMemberDto],
        categories: [DropdownOptionItemDto],
        groups: [TaskManagementFilterOption],
        rooms: [TaskManagementFilterOption]
    ) -> String {
        switch field {
        case .qualityDrawing:
            guard let id = qualityDrawingId else { return "全部" }
            return drawings.first { $0.id == id }?.drawing.name ?? "已選圖面"
        case .status:
            return summary(for: statuses, options: TaskManagementFilterCatalog.statusOptions)
        case .search:
            let t = search.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? "不限" : t
        case .group:
            return summary(for: groupIds, options: groups)
        case .room:
            return summary(for: roomIds, options: rooms)
        case .category:
            return summary(for: categoryIds, options: categories.map { TaskManagementFilterOption(id: $0.id, label: $0.value) })
        case .priority:
            return summary(for: priorities, options: TaskManagementFilterCatalog.priorityOptions)
        case .createdDate:
            return dateRangeSummary(from: createdFrom, to: createdTo)
        case .dueDate:
            return dateRangeSummary(from: dueFrom, to: dueTo)
        case .executor:
            return memberSummary(ids: executorIds, members: members)
        case .reviewer:
            return memberSummary(ids: reviewerIds, members: members)
        }
    }

    private func summary(for ids: [String], options: [TaskManagementFilterOption]) -> String {
        guard !ids.isEmpty else { return "全部" }
        let labels = ids.compactMap { id in options.first { $0.id == id }?.label }
        if labels.count == 1 { return labels[0] }
        return "已選 \(labels.count) 項"
    }

    private func memberSummary(ids: [String], members: [ProjectMemberDto]) -> String {
        guard !ids.isEmpty else { return "全部" }
        let labels = ids.compactMap { id in
            members.first { $0.user.id == id }?.user.displayName
                ?? members.first { $0.user.id == id }?.user.username
        }
        if labels.count == 1 { return labels[0] }
        return "已選 \(labels.count) 項"
    }

    private func dateRangeSummary(from: Date?, to: Date?) -> String {
        let fmt = Self.dateOnlyFormatter
        switch (from, to) {
        case let (f?, t?):
            return "\(fmt.string(from: f)) – \(fmt.string(from: t))"
        case let (f?, nil):
            return "\(fmt.string(from: f)) 起"
        case let (nil, t?):
            return "至 \(fmt.string(from: t))"
        default:
            return "不限"
        }
    }

    private static let dateOnlyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_TW")
        f.dateFormat = "yyyy/MM/dd"
        return f
    }()

    static let isoDateOnlyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()
}

enum TaskManagementFilterField: String, CaseIterable, Identifiable {
    case qualityDrawing
    case status
    case search
    case group
    case room
    case category
    case priority
    case createdDate
    case dueDate
    case executor
    case reviewer

    var id: String { rawValue }

    var title: String {
        switch self {
        case .qualityDrawing: return "平面圖"
        case .status: return "狀態"
        case .search: return "描述"
        case .group: return "群組"
        case .room: return "空間"
        case .category: return "類別"
        case .priority: return "優先級"
        case .createdDate: return "建立時間"
        case .dueDate: return "到期時間"
        case .executor: return "執行人"
        case .reviewer: return "審查人員"
        }
    }

    var needsSubpage: Bool { true }
}

enum TaskManagementFilterCatalog {
    static let statusOptions: [TaskManagementFilterOption] = [
        .init(id: "pending_assignment", label: "待指派"),
        .init(id: "in_progress", label: "進行中"),
        .init(id: "director_check", label: "負責人確認"),
        .init(id: "in_review", label: "審查中"),
        .init(id: "rejected", label: "已退回"),
        .init(id: "approved", label: "已完成"),
    ]

    static let priorityOptions: [TaskManagementFilterOption] = [
        .init(id: "low", label: "低"),
        .init(id: "medium", label: "中"),
        .init(id: "high", label: "高"),
    ]
}
