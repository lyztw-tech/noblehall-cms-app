import Foundation

// MARK: - List

struct QualityTaskListItemDto: Codable, Sendable, Identifiable {
    let id: String
    let projectCode: String?
    let qualityDrawing: QualityDrawingRefDto?
    let name: String?
    let status: String?
    let group: NamedRefDto?
    let room: NamedRefDto?
    let executorId: String?
    let executorType: String?
    let executor: ExecutorRefDto?
    let reviewer: ReviewerDto?
    /// 列表 API 與 `QualityTaskDto` 相同之 `createdAt`；離線暫存列可能為入佇時間。
    let createdAt: Date?
}

struct QualityDrawingRefDto: Codable, Sendable {
    let id: String
    let name: String
}

struct NamedRefDto: Codable, Sendable {
    let id: String
    let name: String
}

struct ExecutorRefDto: Codable, Sendable {
    let id: String?
    let type: String?
    let displayName: String?
    let name: String?
}

struct QualityTaskListResponseDto: Codable, Sendable {
    let data: [QualityTaskListItemDto]
    let pagination: PaginationDto
}

struct CategoryRefDto: Codable, Sendable {
    let id: String
    let value: String
}

/// 與後端任務 DTO `createdBy` 對齊。
struct TaskCreatorRefDto: Codable, Sendable, Hashable {
    let id: String
    let username: String?
    let displayName: String?
}

// MARK: - Detail

struct QualityTaskDto: Codable, Sendable {
    let id: String
    let projectCode: String?
    let qualityDrawing: QualityDrawingRefDto?
    let name: String
    let description: String?
    let status: String?
    let priority: String?
    let categoryId: String?
    let category: CategoryRefDto?
    let groupId: String?
    let group: NamedRefDto?
    let roomId: String?
    let room: NamedRefDto?
    let executorId: String?
    let executorType: String?
    let executor: QualityExecutorDto?
    let reviewer: ReviewerDto?
    let dueDate: Date?
    let createdAt: Date?
    let updatedAt: Date?
    let createdBy: TaskCreatorRefDto?
}

struct QualityExecutorDto: Codable, Sendable {
    let type: String?
    let id: String
    let name: String
    let displayName: String?
    let username: String?
}

struct ReviewerDto: Codable, Sendable {
    let id: String
    let username: String?
    let displayName: String?
}

struct QualityTaskDetailResponseDto: Codable, Sendable {
    let task: QualityTaskDto
    let latestSubmission: QualityTaskSubmissionDto?
    let viewer: ViewerFlagsDto?
    /// 任務流水帳（舊到新），與 Web `QualityTaskLedgerTimeline` 同源。
    let ledger: [TaskLedgerEntryDto]?
}

// MARK: - Task ledger（執行／負責人確認／審核）

enum TaskLedgerEntryKindDto: String, Codable, Sendable, Hashable {
    case execution
    case director_review
    case review
}

struct TaskLedgerActorDto: Codable, Sendable, Hashable {
    let id: String
    let username: String?
    let displayName: String?
}

struct TaskLedgerEntryDto: Codable, Sendable, Identifiable, Hashable {
    let id: String
    let kind: TaskLedgerEntryKindDto
    let occurredAt: Date
    let submissionId: String?
    let round: Int?
    let actor: TaskLedgerActorDto
    let body: String?
    let result: String?
    let attachments: [ExecutionAttachmentDto]?
}

enum TaskLedgerPresentation {
    static func kindLabel(_ kind: TaskLedgerEntryKindDto) -> String {
        switch kind {
        case .execution: return "執行"
        case .director_review: return "負責人確認"
        case .review: return "審核"
        }
    }

    /// 與 Web `QualityTaskExecutionModal` / 後端 `updateExecution` 一致：未送出、建立者本人、日曆三天內、任務為進行中。
    static func canModifyDraftExecution(
        entry: TaskLedgerEntryDto,
        task: QualityTaskDto,
        currentUserId: String?
    ) -> Bool {
        guard entry.kind == .execution else { return false }
        guard entry.submissionId == nil else { return false }
        guard let uid = currentUserId, !uid.isEmpty, uid == entry.actor.id else { return false }
        let st = QualityTaskEditEligibility.normalizedStatus(task.status)
        guard st == "in_progress" else { return false }
        return QualityTaskEditEligibility.isCreatedWithinLastCalendarDays(entry.occurredAt, days: 3)
    }

    /// `nil` 表示可編輯（仍須連線，由 UI 另判斷）；否則為不可編輯原因。
    static func draftExecutionEditBlockedReason(
        entry: TaskLedgerEntryDto,
        task: QualityTaskDto,
        currentUserId: String?,
        isOnline: Bool
    ) -> String? {
        if isOnline, canModifyDraftExecution(entry: entry, task: task, currentUserId: currentUserId) { return nil }
        if !isOnline { return "離線時無法編輯執行說明。" }
        if entry.kind != .execution { return "僅「執行」紀錄可編輯說明。" }
        if entry.submissionId != nil { return "已送出後無法再編輯此筆說明。" }
        if let uid = currentUserId, !uid.isEmpty {
            if uid != entry.actor.id { return "僅建立此筆紀錄的人員可編輯。" }
        } else {
            return "無法確認使用者身分，無法編輯。"
        }
        let st = QualityTaskEditEligibility.normalizedStatus(task.status)
        if st != "in_progress" { return "僅任務為「進行中」時可編輯執行說明。" }
        if !QualityTaskEditEligibility.isCreatedWithinLastCalendarDays(entry.occurredAt, days: 3) {
            return "此筆紀錄已超過三天，無法編輯。"
        }
        return "目前無法編輯。"
    }
}

struct QualityTaskSubmissionDto: Codable, Sendable {
    let id: String?
    let executions: [ExecutionRecordDto]?
}

struct ExecutionAttachmentDto: Codable, Sendable, Identifiable, Hashable {
    let id: String
    let originalFilename: String?
    let fileSize: Int?
    let mimeType: String?
    let url: String?
    let thumbnailUrl: String?
}

struct ExecutionRecordDto: Codable, Sendable, Identifiable {
    let id: String
    let executionReply: String?
    let executedAt: Date?
    let createdAt: Date?
    /// 已關聯 submission 時不為 nil；與 Web 判斷「草稿可編輯」一致。
    let submissionId: String?
    let executor: ExecutorUserDto?
    let attachments: [ExecutionAttachmentDto]?
}

struct ExecutorUserDto: Codable, Sendable {
    let id: String
    let username: String?
    let displayName: String?
}

extension TaskLedgerPresentation {
    /// `latestSubmission.executions` 無 ledger 時之草稿列；規則與 `canModifyDraftExecution` 對齊。
    static func canModifyFallbackExecution(
        ex: ExecutionRecordDto,
        task: QualityTaskDto,
        currentUserId: String?
    ) -> Bool {
        guard ex.submissionId == nil else { return false }
        guard let uid = currentUserId, !uid.isEmpty, let eid = ex.executor?.id, eid == uid else { return false }
        guard QualityTaskEditEligibility.normalizedStatus(task.status) == "in_progress" else { return false }
        let ref = ex.executedAt ?? ex.createdAt
        return QualityTaskEditEligibility.isCreatedWithinLastCalendarDays(ref, days: 3)
    }

    static func fallbackExecutionEditBlockedReason(
        ex: ExecutionRecordDto,
        task: QualityTaskDto,
        currentUserId: String?,
        isOnline: Bool
    ) -> String? {
        if isOnline, canModifyFallbackExecution(ex: ex, task: task, currentUserId: currentUserId) { return nil }
        if !isOnline { return "離線時無法編輯執行說明。" }
        if ex.submissionId != nil { return "已送出後無法再編輯此筆說明。" }
        if let uid = currentUserId, !uid.isEmpty, let eid = ex.executor?.id, eid != uid {
            return "僅建立此筆紀錄的人員可編輯。"
        } else if currentUserId == nil || (currentUserId?.isEmpty == true) {
            return "無法確認使用者身分，無法編輯。"
        }
        if QualityTaskEditEligibility.normalizedStatus(task.status) != "in_progress" {
            return "僅任務為「進行中」時可編輯執行說明。"
        }
        let ref = ex.executedAt ?? ex.createdAt
        if !QualityTaskEditEligibility.isCreatedWithinLastCalendarDays(ref, days: 3) {
            return "此筆紀錄已超過三天，無法編輯。"
        }
        return "目前無法編輯。"
    }

    static func ledgerEntryFromFallbackExecution(_ ex: ExecutionRecordDto) -> TaskLedgerEntryDto {
        let actorId = ex.executor?.id ?? ""
        return TaskLedgerEntryDto(
            id: ex.id,
            kind: .execution,
            occurredAt: ex.executedAt ?? ex.createdAt ?? Date(),
            submissionId: ex.submissionId,
            round: nil,
            actor: TaskLedgerActorDto(
                id: actorId,
                username: ex.executor?.username,
                displayName: ex.executor?.displayName
            ),
            body: ex.executionReply,
            result: nil,
            attachments: ex.attachments
        )
    }
}

struct ViewerFlagsDto: Codable, Sendable {
    let isProjectOwner: Bool?
    let canAssignQualityTask: Bool?
    let canUpdateQualityTask: Bool?
}

// MARK: - Drawing & room points

struct QualityDrawingDetailDto: Codable, Sendable {
    let id: String
    let drawing: DrawingDetailInnerDto
}

struct DrawingDetailInnerDto: Codable, Sendable {
    let id: String
    let name: String
    let file: DrawingFileDto?
}

struct DrawingFileDto: Codable, Sendable {
    let id: String
    let originalFilename: String?
    let url: String?
    let thumbnailUrl: String?
}

struct QualityTaskRoomPointDto: Codable, Sendable, Identifiable {
    let id: String
    let groupId: String?
    let x: Double
    let y: Double
    let name: String
    let taskCount: Int?
    let incompleteTaskCount: Int?
}

// MARK: - API bodies

struct CreateExecutionBody: Encodable, Sendable {
    let executionReply: String?
}

struct SubmitExecutionBody: Encodable, Sendable {
    let executionIds: [String]?
    let newExecution: CreateExecutionBody?

    static let savedExecutionsOnly = SubmitExecutionBody(executionIds: nil, newExecution: nil)
}

struct UpdateExecutionBody: Encodable, Sendable {
    let executionReply: String?
}

enum QualityTaskReviewResult: String, Encodable, Sendable {
    case approved
    case rejected
}

struct ReviewSubmissionBody: Encodable, Sendable {
    let reviewResult: QualityTaskReviewResult
    let reviewComment: String?
}

struct CreateExecutionResponseDto: Decodable, Sendable {
    let id: String?
    let uuid: String?
    let uploadWarnings: [CreateExecutionUploadWarningDto]?
}

struct CreateExecutionUploadWarningDto: Decodable, Sendable {
    let filename: String
    let error: String
}

/// POST `.../executions/:id/attachments`（`data` 於 201／207 形狀不同，僅解碼頂層欄位即可）。
struct UploadExecutionAttachmentsResponseDto: Decodable, Sendable {
    let success: Bool?
    let message: String?
}

/// POST review attachment endpoints use the same top-level response shape as execution attachment uploads.
typealias UploadReviewAttachmentsResponseDto = UploadExecutionAttachmentsResponseDto

// MARK: - Quality drawings list

struct QualityDrawingTaskCountByStatusDto: Codable, Sendable, Hashable {
    let pendingAssignmentCount: Int
    let inProgressCount: Int
    let directorCheckCount: Int
    let inReviewCount: Int
    let approvedCount: Int

    static let zero = QualityDrawingTaskCountByStatusDto(
        pendingAssignmentCount: 0,
        inProgressCount: 0,
        directorCheckCount: 0,
        inReviewCount: 0,
        approvedCount: 0
    )
}

struct QualityDrawingListItemDto: Codable, Sendable, Identifiable {
    let id: String
    let drawing: QualityDrawingRefDto
    let taskCount: Int?
    let taskCountByStatus: QualityDrawingTaskCountByStatusDto?
}

struct QualityDrawingListResponseDto: Codable, Sendable {
    let data: [QualityDrawingListItemDto]
    let pagination: PaginationDto
}

// MARK: - Create task

struct CreateQualityTaskBody: Codable, Sendable {
    let name: String
    let description: String?
    let categoryId: String?
    let groupId: String?
    let roomId: String?
    let executorId: String?
    let executorType: String?
    let reviewerId: String
    let priority: String
    let dueDate: String?
}

/// 建立任務 API 回傳完整 `QualityTaskDto`；僅需 `id` 時用此型別解碼。
typealias CreateQualityTaskResponseDto = QualityTaskDto

// MARK: - Update task

/// PATCH `projects/:projectCode/quality-tasks/:taskId`（對齊後端 `updateQualityTaskSchema`）。
struct UpdateQualityTaskBody: Encodable, Sendable {
    /// 為 `false` 時不輸出 `name`／`description`／`priority`（建立逾 3 日僅改審查人／執行對象時使用）。
    let includeCoreTaskFields: Bool
    let name: String
    /// 可為空字串；與後端 `description` 字串欄位對齊。
    let description: String
    let priority: String
    /// 為 `true` 時輸出 `dueDate` 鍵：有值為 ISO8601 字串，無值為 JSON `null`（清除到期日）。
    let includeDueDateInPayload: Bool
    let dueDate: String?
    /// 分別控制；避免僅載入到成員列表卻用 `null` 誤清類別（或相反）。
    let includeCategoryId: Bool
    let includeReviewerId: Bool
    let includeExecutorFields: Bool
    /// 空字串表示 JSON `null`（清除）；僅在對應 `include*` 為 `true` 時輸出鍵。
    let categoryId: String
    let reviewerId: String
    let executorId: String
    let executorType: String?

    enum CodingKeys: String, CodingKey {
        case name, description, priority, dueDate, categoryId, reviewerId, executorId, executorType
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        if includeCoreTaskFields {
            try c.encode(name, forKey: .name)
            try c.encode(description, forKey: .description)
            try c.encode(priority, forKey: .priority)
        }
        if includeDueDateInPayload {
            if let dueDate, !dueDate.isEmpty {
                try c.encode(dueDate, forKey: .dueDate)
            } else {
                try c.encodeNil(forKey: .dueDate)
            }
        }
        if includeCategoryId {
            if categoryId.isEmpty {
                try c.encodeNil(forKey: .categoryId)
            } else {
                try c.encode(categoryId, forKey: .categoryId)
            }
        }
        if includeReviewerId {
            if reviewerId.isEmpty {
                try c.encodeNil(forKey: .reviewerId)
            } else {
                try c.encode(reviewerId, forKey: .reviewerId)
            }
        }
        if includeExecutorFields {
            if executorId.isEmpty || executorType == nil {
                try c.encodeNil(forKey: .executorId)
                try c.encodeNil(forKey: .executorType)
            } else {
                try c.encode(executorId, forKey: .executorId)
                try c.encode(executorType, forKey: .executorType)
            }
        }
    }
}

/// 更新任務 API 回傳與建立相同之 `QualityTaskDto`。
typealias UpdateQualityTaskResponseDto = QualityTaskDto

// MARK: - Project members / groups (表單用)

struct ProjectMemberUserDto: Codable, Sendable {
    let id: String
    let username: String?
    let displayName: String?
}

struct ProjectMemberDto: Codable, Sendable, Identifiable {
    let id: String
    let memberCategory: String?
    let user: ProjectMemberUserDto
}

struct ProjectMemberListResponseDto: Codable, Sendable {
    let data: [ProjectMemberDto]
    let pagination: PaginationDto
}

struct ProjectGroupDto: Codable, Sendable, Identifiable {
    let id: String
    let name: String
    let ownerId: String?
}

struct ProjectGroupListResponseDto: Codable, Sendable {
    let data: [ProjectGroupDto]
}

// MARK: - Dropdown options

struct DropdownOptionItemDto: Codable, Sendable, Identifiable {
    let id: String
    let value: String
}

struct DropdownFieldDto: Codable, Sendable {
    let businessType: String
    let fieldName: String
    let options: [DropdownOptionItemDto]
}
