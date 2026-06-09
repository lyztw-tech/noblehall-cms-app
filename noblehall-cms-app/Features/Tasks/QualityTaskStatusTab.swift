import Foundation

/// 任務列表狀態分段（我的任務、任務管理－全部任務共用）。
enum QualityTaskStatusTab: String, CaseIterable, Identifiable, Hashable {
    case pendingAssignment = "待指派"
    case inProgress = "執行中"
    /// 含 `director_check`（負責人確認）與 `in_review`（審查中）。
    case inReview = "待審核"

    var id: String { rawValue }

    func matches(status: String?) -> Bool {
        let normalized = QualityTaskEditEligibility.normalizedStatus(status)
        switch self {
        case .pendingAssignment:
            return normalized == "pending_assignment" || normalized == "待指派"
        case .inProgress:
            return normalized == "in_progress"
                || normalized == "rejected"
                || normalized == "執行中"
                || normalized == "進行中"
                || normalized == "已退回"
        case .inReview:
            return normalized == "in_review"
                || normalized == "director_check"
                || normalized == "待審核"
                || normalized == "審查中"
                || normalized == "負責人確認"
        }
    }

    static func tab(for status: String?) -> QualityTaskStatusTab? {
        allCases.first { $0.matches(status: status) }
    }
}
