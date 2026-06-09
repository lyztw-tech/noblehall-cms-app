import Foundation

/// 與 Web 任務管理詳情（`QualityTaskManagementDetailView`）/ `quality-task-edit-window.ts` 對齊的任務編輯資格。
enum QualityTaskEditEligibility {
    /// 建立後可編輯「完整」基本資料的天數（逾此僅能改審查人等指派欄位）。
    static let basicInfoFullEditWindowDays = 3

    static func normalizedStatus(_ raw: String?) -> String {
        let normalized = (raw ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
        switch normalized {
        case "unassigned": return "pending_assignment"
        case "pending_owner_confirmation": return "director_check"
        case "pending_review": return "in_review"
        case "returned": return "rejected"
        case "completed": return "approved"
        default: return normalized
        }
    }

    /// 與 Web 任務管理詳情 `allowWorkbenchBasicInfoEdit`：進入審核／負責人確認／已完成後不可再編輯基本資料。
    static func allowsBasicInfoEdit(task: QualityTaskDto) -> Bool {
        let s = normalizedStatus(task.status)
        switch s {
        case "in_review", "director_check", "approved":
            return false
        default:
            return true
        }
    }

    /// 與 Web `isTaskCreatedWithinCalendarDays`（日曆日邊界，與 `isTimestampWithinLastCalendarDays` 一致）。
    static func isCreatedWithinLastCalendarDays(_ createdAt: Date?, days: Int) -> Bool {
        guard let createdAt else { return false }
        guard let boundary = Calendar.current.date(byAdding: .day, value: -days, to: Date()) else { return false }
        return createdAt >= boundary
    }

    /// 與 Web `basicInfoNonAssignmentFieldsLocked`：建立逾 N 日後，非指派欄位鎖定（仍允許開啟編輯改審查人等）。
    static func nonAssignmentFieldsLocked(task: QualityTaskDto) -> Bool {
        !allowsBasicInfoEdit(task: task)
            || !isCreatedWithinLastCalendarDays(task.createdAt, days: basicInfoFullEditWindowDays)
    }

    static func isCurrentUserCreator(task: QualityTaskDto, userId: String?) -> Bool {
        guard let uid = userId, !uid.isEmpty else { return false }
        guard let cid = task.createdBy?.id, !cid.isEmpty else { return false }
        return uid == cid
    }

    /// 無法開啟「編輯任務」時的人類可讀原因（`nil` 表示可開啟）。
    static func taskEditSheetBlockedReason(
        task: QualityTaskDto,
        userId: String?,
        isOnline: Bool,
        hasQualityDrawing: Bool,
        canAssignQualityTasks: Bool
    ) -> String? {
        if !isOnline { return "離線時無法編輯任務。" }
        if !hasQualityDrawing { return "缺少品質圖面資訊，無法更新任務。" }
        if !isCurrentUserCreator(task: task, userId: userId), !canAssignQualityTasks {
            return "僅限建立任務的人員可編輯。"
        }
        return nil
    }
}
