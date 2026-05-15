import Foundation

/// 與 Web `QUALITY_TASK_STATUS_CONFIG` 標籤對齊。
enum QualityTaskStatusLabels {
    static func displayName(for status: String?) -> String {
        let normalized = (status ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
            .replacingOccurrences(of: " ", with: "_")
        guard !normalized.isEmpty else { return "—" }
        switch normalized {
        case "info": return "資訊"
        case "pending_assignment", "待指派": return "待指派"
        case "in_progress", "執行中", "進行中": return "進行中"
        case "director_check": return "負責人確認"
        case "in_review", "待審核", "審查中": return "審查中"
        case "rejected": return "已退回"
        case "approved": return "已完成"
        default:
            if status?.range(of: "[\u{4e00}-\u{9fff}]", options: .regularExpression) != nil {
                return status ?? normalized
            }
            return normalized.replacingOccurrences(of: "_", with: " ")
        }
    }
}
