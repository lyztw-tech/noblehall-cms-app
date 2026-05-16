import Foundation

/// 任務列表狀態分段（我的任務、任務管理－全部任務共用）。
enum QualityTaskStatusTab: String, CaseIterable, Identifiable, Hashable {
    case pendingAssignment = "待指派"
    case inProgress = "執行中"
    case inReview = "待審核"

    var id: String { rawValue }

    func matches(status: String?) -> Bool {
        let normalized = (status ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
        switch self {
        case .pendingAssignment:
            return normalized == "pending_assignment" || normalized == "待指派"
        case .inProgress:
            return normalized == "in_progress" || normalized == "執行中" || normalized == "進行中"
        case .inReview:
            return normalized == "in_review" || normalized == "待審核" || normalized == "審查中"
        }
    }
}
