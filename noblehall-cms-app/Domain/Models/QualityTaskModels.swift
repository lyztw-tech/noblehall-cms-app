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
    let executor: ExecutorRefDto?
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
        let st = (task.status ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
        guard st == "in_progress" else { return false }
        guard let threeDaysAgo = Calendar.current.date(byAdding: .day, value: -3, to: Date()) else { return false }
        return entry.occurredAt >= threeDaysAgo
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

struct ViewerFlagsDto: Codable, Sendable {
    let isProjectOwner: Bool?
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

struct UpdateExecutionBody: Encodable, Sendable {
    let executionReply: String?
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
    /// 為 `false` 時不輸出 `name`／`description`／`priority`／`status`（建立逾 3 日僅改審查人等指派欄位時使用）。
    let includeCoreTaskFields: Bool
    let name: String
    /// 可為空字串；與後端 `description` 字串欄位對齊。
    let description: String
    let priority: String
    let status: String
    /// 為 `true` 時輸出 `dueDate` 鍵：有值為 ISO8601 字串，無值為 JSON `null`（清除到期日）。
    let includeDueDateInPayload: Bool
    let dueDate: String?
    /// 分別控制；避免僅載入到成員列表卻用 `null` 誤清類別（或相反）。
    let includeCategoryId: Bool
    let includeReviewerId: Bool
    /// 空字串表示 JSON `null`（清除）；僅在對應 `include*` 為 `true` 時輸出鍵。
    let categoryId: String
    let reviewerId: String

    enum CodingKeys: String, CodingKey {
        case name, description, priority, status, dueDate, categoryId, reviewerId
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        if includeCoreTaskFields {
            try c.encode(name, forKey: .name)
            try c.encode(description, forKey: .description)
            try c.encode(priority, forKey: .priority)
            try c.encode(status, forKey: .status)
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
