import Foundation
import SwiftUI

/// 任務管理：平面圖詳情狀態卡片（與 Web 品質圖面列表欄位對齊）。
enum TaskManagementStatusFilter: String, CaseIterable, Identifiable, Hashable {
    case pendingAssignment
    case executing
    case directorCheck
    case inReview
    case approved

    var id: String { rawValue }

    var title: String {
        switch self {
        case .pendingAssignment: return "待指派"
        case .executing: return "進行中"
        case .directorCheck: return "負責人確認"
        case .inReview: return "審查中"
        case .approved: return "已完成"
        }
    }

    /// 後端 `status` query（`executing` = 進行中 + 已退回，與 Web `taskStatus=executing` 一致）。
    var apiStatuses: [String] {
        switch self {
        case .pendingAssignment: return ["pending_assignment"]
        case .executing: return ["in_progress", "rejected"]
        case .directorCheck: return ["director_check"]
        case .inReview: return ["in_review"]
        case .approved: return ["approved"]
        }
    }

    func count(in stats: QualityDrawingTaskCountByStatusDto) -> Int {
        switch self {
        case .pendingAssignment: return stats.pendingAssignmentCount
        case .executing: return stats.inProgressCount
        case .directorCheck: return stats.directorCheckCount
        case .inReview: return stats.inReviewCount
        case .approved: return stats.approvedCount
        }
    }

    var tint: Color {
        switch self {
        case .pendingAssignment: return Color(white: 0.45)
        case .executing: return Color(red: 0.08, green: 0.28, blue: 0.9)
        case .directorCheck: return Color(red: 0.49, green: 0.23, blue: 0.93)
        case .inReview: return Color(red: 0.82, green: 0.53, blue: 0)
        case .approved: return Color(red: 0.13, green: 0.55, blue: 0.13)
        }
    }

    func matches(taskStatus: String?) -> Bool {
        let normalized = QualityTaskEditEligibility.normalizedStatus(taskStatus)
        switch self {
        case .pendingAssignment:
            return normalized == "pending_assignment"
        case .executing:
            return normalized == "in_progress" || normalized == "rejected"
        case .directorCheck:
            return normalized == "director_check"
        case .inReview:
            return normalized == "in_review"
        case .approved:
            return normalized == "approved"
        }
    }
}
