import Foundation

// MARK: - List

struct QualityTaskListItemDto: Decodable, Sendable, Identifiable {
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

    enum CodingKeys: String, CodingKey {
        case id, projectCode, projectId, qualityDrawing, floor, name, status, group, room, space
        case executorId, executorType, executor, reviewer, createdAt
    }

    init(
        id: String,
        projectCode: String?,
        qualityDrawing: QualityDrawingRefDto?,
        name: String?,
        status: String?,
        group: NamedRefDto?,
        room: NamedRefDto?,
        executorId: String?,
        executorType: String?,
        executor: ExecutorRefDto?,
        reviewer: ReviewerDto?,
        createdAt: Date?
    ) {
        self.id = id
        self.projectCode = projectCode
        self.qualityDrawing = qualityDrawing
        self.name = name
        self.status = QualityTaskEditEligibility.normalizedStatus(status)
        self.group = group
        self.room = room
        self.executorId = executorId
        self.executorType = executorType
        self.executor = executor
        self.reviewer = reviewer
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let projectId = try c.decodeIfPresent(String.self, forKey: .projectId)
        let floor = try c.decodeIfPresent(QualityDrawingRefDto.self, forKey: .floor)
        let space = try c.decodeIfPresent(NamedRefDto.self, forKey: .space)
        self.init(
            id: try c.decode(String.self, forKey: .id),
            projectCode: try c.decodeIfPresent(String.self, forKey: .projectCode) ?? projectId,
            qualityDrawing: try c.decodeIfPresent(QualityDrawingRefDto.self, forKey: .qualityDrawing) ?? floor,
            name: try c.decodeIfPresent(String.self, forKey: .name),
            status: try c.decodeIfPresent(String.self, forKey: .status),
            group: try c.decodeIfPresent(NamedRefDto.self, forKey: .group),
            room: try c.decodeIfPresent(NamedRefDto.self, forKey: .room) ?? space,
            executorId: try c.decodeIfPresent(String.self, forKey: .executorId),
            executorType: try c.decodeIfPresent(String.self, forKey: .executorType) ?? "user",
            executor: try c.decodeIfPresent(ExecutorRefDto.self, forKey: .executor),
            reviewer: try c.decodeIfPresent(ReviewerDto.self, forKey: .reviewer),
            createdAt: try c.decodeIfPresent(Date.self, forKey: .createdAt)
        )
    }
}

struct QualityDrawingRefDto: Codable, Sendable {
    let id: String
    let name: String
}

struct NamedRefDto: Codable, Sendable {
    let id: String
    let name: String
}

struct ExecutorRefDto: Decodable, Sendable {
    let id: String?
    let type: String?
    let displayName: String?
    let name: String?

    enum CodingKeys: String, CodingKey {
        case id, type, displayName, name, email
    }

    init(id: String?, type: String?, displayName: String?, name: String?) {
        self.id = id
        self.type = type
        self.displayName = displayName
        self.name = name
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let name = try c.decodeIfPresent(String.self, forKey: .name)
        let email = try c.decodeIfPresent(String.self, forKey: .email)
        id = try c.decodeIfPresent(String.self, forKey: .id)
        type = try c.decodeIfPresent(String.self, forKey: .type) ?? "user"
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName) ?? name ?? email
        self.name = name ?? email
    }
}

struct QualityTaskListResponseDto: Decodable, Sendable {
    let data: [QualityTaskListItemDto]
    let pagination: PaginationDto

    enum CodingKeys: String, CodingKey {
        case data, pagination, meta
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        data = try c.decode([QualityTaskListItemDto].self, forKey: .data)
        pagination = try c.decodeIfPresent(PaginationDto.self, forKey: .pagination)
            ?? c.decodeIfPresent(PaginationDto.self, forKey: .meta)
            ?? PaginationDto(page: 1, limit: data.count, total: data.count)
    }
}

struct CategoryRefDto: Decodable, Sendable {
    let id: String
    let value: String

    enum CodingKeys: String, CodingKey {
        case id, value, name
    }

    init(id: String, value: String) {
        self.id = id
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        value = try c.decodeIfPresent(String.self, forKey: .value)
            ?? c.decodeIfPresent(String.self, forKey: .name)
            ?? id
    }
}

/// 與後端任務 DTO `createdBy` 對齊。
struct TaskCreatorRefDto: Decodable, Sendable, Hashable {
    let id: String
    let username: String?
    let displayName: String?

    enum CodingKeys: String, CodingKey {
        case id, username, displayName, name, email
    }

    init(id: String, username: String?, displayName: String?) {
        self.id = id
        self.username = username
        self.displayName = displayName
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        username = try c.decodeIfPresent(String.self, forKey: .username) ?? c.decodeIfPresent(String.self, forKey: .email)
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName) ?? c.decodeIfPresent(String.self, forKey: .name)
    }
}

// MARK: - Detail

struct QualityTaskDto: Decodable, Sendable {
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

    enum CodingKeys: String, CodingKey {
        case id, projectCode, projectId, qualityDrawing, floor, name, description, status, priority
        case categoryId, category, groupId, group, roomId, room, spaceId, space
        case executorId, executorType, executor, reviewer, dueDate, dueAt, createdAt, updatedAt, createdBy
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let projectId = try c.decodeIfPresent(String.self, forKey: .projectId)
        let floor = try c.decodeIfPresent(QualityDrawingRefDto.self, forKey: .floor)
        let space = try c.decodeIfPresent(NamedRefDto.self, forKey: .space)
        id = try c.decode(String.self, forKey: .id)
        projectCode = try c.decodeIfPresent(String.self, forKey: .projectCode) ?? projectId
        qualityDrawing = try c.decodeIfPresent(QualityDrawingRefDto.self, forKey: .qualityDrawing) ?? floor
        name = try c.decode(String.self, forKey: .name)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        status = QualityTaskEditEligibility.normalizedStatus(try c.decodeIfPresent(String.self, forKey: .status))
        priority = try c.decodeIfPresent(String.self, forKey: .priority)
        categoryId = try c.decodeIfPresent(String.self, forKey: .categoryId)
        category = try c.decodeIfPresent(CategoryRefDto.self, forKey: .category)
        groupId = try c.decodeIfPresent(String.self, forKey: .groupId)
        group = try c.decodeIfPresent(NamedRefDto.self, forKey: .group)
        roomId = try c.decodeIfPresent(String.self, forKey: .roomId) ?? c.decodeIfPresent(String.self, forKey: .spaceId)
        room = try c.decodeIfPresent(NamedRefDto.self, forKey: .room) ?? space
        executorId = try c.decodeIfPresent(String.self, forKey: .executorId)
        executorType = try c.decodeIfPresent(String.self, forKey: .executorType) ?? "user"
        executor = try c.decodeIfPresent(QualityExecutorDto.self, forKey: .executor)
        reviewer = try c.decodeIfPresent(ReviewerDto.self, forKey: .reviewer)
        dueDate = try c.decodeIfPresent(Date.self, forKey: .dueDate) ?? c.decodeIfPresent(Date.self, forKey: .dueAt)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt)
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt)
        createdBy = try c.decodeIfPresent(TaskCreatorRefDto.self, forKey: .createdBy)
    }
}

struct QualityExecutorDto: Decodable, Sendable {
    let type: String?
    let id: String
    let name: String
    let displayName: String?
    let username: String?

    enum CodingKeys: String, CodingKey {
        case type, id, name, displayName, username, email
    }

    init(type: String?, id: String, name: String, displayName: String?, username: String?) {
        self.type = type
        self.id = id
        self.name = name
        self.displayName = displayName
        self.username = username
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        let decodedName = try c.decodeIfPresent(String.self, forKey: .name)
        let email = try c.decodeIfPresent(String.self, forKey: .email)
        type = try c.decodeIfPresent(String.self, forKey: .type) ?? "user"
        name = decodedName ?? email ?? id
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName) ?? decodedName
        username = try c.decodeIfPresent(String.self, forKey: .username) ?? email
    }
}

struct ReviewerDto: Decodable, Sendable {
    let id: String
    let username: String?
    let displayName: String?

    enum CodingKeys: String, CodingKey {
        case id, username, displayName, name, email
    }

    init(id: String, username: String?, displayName: String?) {
        self.id = id
        self.username = username
        self.displayName = displayName
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        username = try c.decodeIfPresent(String.self, forKey: .username) ?? c.decodeIfPresent(String.self, forKey: .email)
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName) ?? c.decodeIfPresent(String.self, forKey: .name)
    }
}

struct QualityTaskDetailResponseDto: Decodable, Sendable {
    let task: QualityTaskDto
    let latestSubmission: QualityTaskSubmissionDto?
    let viewer: ViewerFlagsDto?
    /// 任務流水帳（舊到新），與 Web `QualityTaskLedgerTimeline` 同源。
    let ledger: [TaskLedgerEntryDto]?

    init(
        task: QualityTaskDto,
        latestSubmission: QualityTaskSubmissionDto?,
        viewer: ViewerFlagsDto?,
        ledger: [TaskLedgerEntryDto]?
    ) {
        self.task = task
        self.latestSubmission = latestSubmission
        self.viewer = viewer
        self.ledger = ledger
    }
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

struct TaskLedgerEntryDto: Decodable, Sendable, Identifiable, Hashable {
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

struct QualityTaskSubmissionDto: Decodable, Sendable {
    let id: String?
    let executions: [ExecutionRecordDto]?

    init(id: String?, executions: [ExecutionRecordDto]?) {
        self.id = id
        self.executions = executions
    }
}

struct ExecutionAttachmentDto: Decodable, Sendable, Identifiable, Hashable {
    let id: String
    let originalFilename: String?
    let fileSize: Int?
    let mimeType: String?
    let url: String?
    let thumbnailUrl: String?

    enum CodingKeys: String, CodingKey {
        case id, originalFilename, fileName, fileSize, mimeType, url, thumbnailUrl
    }

    init(
        id: String,
        originalFilename: String?,
        fileSize: Int?,
        mimeType: String?,
        url: String?,
        thumbnailUrl: String?
    ) {
        self.id = id
        self.originalFilename = originalFilename
        self.fileSize = fileSize
        self.mimeType = mimeType
        self.url = url
        self.thumbnailUrl = thumbnailUrl
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        originalFilename = try c.decodeIfPresent(String.self, forKey: .originalFilename)
            ?? c.decodeIfPresent(String.self, forKey: .fileName)
        fileSize = try c.decodeIfPresent(Int.self, forKey: .fileSize)
        mimeType = try c.decodeIfPresent(String.self, forKey: .mimeType)
        url = try c.decodeIfPresent(String.self, forKey: .url)
        thumbnailUrl = try c.decodeIfPresent(String.self, forKey: .thumbnailUrl)
    }
}

struct ExecutionRecordDto: Decodable, Sendable, Identifiable {
    let id: String
    let executionReply: String?
    let executedAt: Date?
    let createdAt: Date?
    /// 已關聯 submission 時不為 nil；與 Web 判斷「草稿可編輯」一致。
    let submissionId: String?
    let executor: ExecutorUserDto?
    let attachments: [ExecutionAttachmentDto]?

    enum CodingKeys: String, CodingKey {
        case id, executionReply, content, executedAt, createdAt, submissionId, executor, createdBy, attachments, photos
    }

    init(
        id: String,
        executionReply: String?,
        executedAt: Date?,
        createdAt: Date?,
        submissionId: String?,
        executor: ExecutorUserDto?,
        attachments: [ExecutionAttachmentDto]?
    ) {
        self.id = id
        self.executionReply = executionReply
        self.executedAt = executedAt
        self.createdAt = createdAt
        self.submissionId = submissionId
        self.executor = executor
        self.attachments = attachments
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        executionReply = try c.decodeIfPresent(String.self, forKey: .executionReply)
            ?? c.decodeIfPresent(String.self, forKey: .content)
        executedAt = try c.decodeIfPresent(Date.self, forKey: .executedAt)
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt)
        submissionId = try c.decodeIfPresent(String.self, forKey: .submissionId)
        executor = try c.decodeIfPresent(ExecutorUserDto.self, forKey: .executor)
            ?? c.decodeIfPresent(ExecutorUserDto.self, forKey: .createdBy)
        attachments = try c.decodeIfPresent([ExecutionAttachmentDto].self, forKey: .attachments)
            ?? c.decodeIfPresent([ExecutionAttachmentDto].self, forKey: .photos)
    }
}

struct ExecutorUserDto: Decodable, Sendable {
    let id: String
    let username: String?
    let displayName: String?

    enum CodingKeys: String, CodingKey {
        case id, username, displayName, name, email
    }

    init(id: String, username: String?, displayName: String?) {
        self.id = id
        self.username = username
        self.displayName = displayName
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        username = try c.decodeIfPresent(String.self, forKey: .username) ?? c.decodeIfPresent(String.self, forKey: .email)
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName) ?? c.decodeIfPresent(String.self, forKey: .name)
    }
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
}

// MARK: - Drawing & room points

struct QualityDrawingDetailDto: Decodable, Sendable {
    let id: String
    let drawing: DrawingDetailInnerDto

    enum CodingKeys: String, CodingKey {
        case id, drawing, name, attachmentId
    }

    init(id: String, drawing: DrawingDetailInnerDto) {
        self.id = id
        self.drawing = drawing
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        if let drawing = try c.decodeIfPresent(DrawingDetailInnerDto.self, forKey: .drawing) {
            self.drawing = drawing
        } else {
            let name = try c.decodeIfPresent(String.self, forKey: .name) ?? "樓層"
            let attachmentId = try c.decodeIfPresent(String.self, forKey: .attachmentId)
            self.drawing = DrawingDetailInnerDto(
                id: id,
                name: name,
                file: attachmentId.map {
                    DrawingFileDto(
                        id: $0,
                        originalFilename: nil,
                        url: "files/\($0)",
                        thumbnailUrl: nil
                    )
                }
            )
        }
    }
}

struct DrawingDetailInnerDto: Codable, Sendable {
    let id: String
    let name: String
    let file: DrawingFileDto?

    init(id: String, name: String, file: DrawingFileDto?) {
        self.id = id
        self.name = name
        self.file = file
    }
}

struct DrawingFileDto: Codable, Sendable {
    let id: String
    let originalFilename: String?
    let url: String?
    let thumbnailUrl: String?

    init(id: String, originalFilename: String?, url: String?, thumbnailUrl: String?) {
        self.id = id
        self.originalFilename = originalFilename
        self.url = url
        self.thumbnailUrl = thumbnailUrl
    }
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

nonisolated struct SubmitExecutionBody: Encodable, Sendable {
    let executionIds: [String]?
    let newExecution: CreateExecutionBody?

    nonisolated static let savedExecutionsOnly = SubmitExecutionBody(executionIds: nil, newExecution: nil)
}

struct EmptyRequestBody: Encodable, Sendable {}

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

    init(id: String?, uuid: String?, uploadWarnings: [CreateExecutionUploadWarningDto]?) {
        self.id = id
        self.uuid = uuid
        self.uploadWarnings = uploadWarnings
    }
}

struct CreateExecutionUploadWarningDto: Decodable, Sendable {
    let filename: String
    let error: String
}

/// POST `.../executions/:id/attachments`（`data` 於 201／207 形狀不同，僅解碼頂層欄位即可）。
struct UploadExecutionAttachmentsResponseDto: Decodable, Sendable {
    let success: Bool?
    let message: String?

    init(success: Bool?, message: String?) {
        self.success = success
        self.message = message
    }
}

/// POST review attachment endpoints use the same top-level response shape as execution attachment uploads.
typealias UploadReviewAttachmentsResponseDto = UploadExecutionAttachmentsResponseDto

struct UploadedFileDto: Decodable, Sendable {
    let id: String
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

struct QualityDrawingListItemDto: Decodable, Sendable, Identifiable {
    let id: String
    let drawing: QualityDrawingRefDto
    let taskCount: Int?
    let taskCountByStatus: QualityDrawingTaskCountByStatusDto?

    init(id: String, drawing: QualityDrawingRefDto, taskCount: Int?, taskCountByStatus: QualityDrawingTaskCountByStatusDto?) {
        self.id = id
        self.drawing = drawing
        self.taskCount = taskCount
        self.taskCountByStatus = taskCountByStatus
    }

    enum CodingKeys: String, CodingKey {
        case id, drawing, name, taskCount, taskCountByStatus, groupCount, spaceCount
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        drawing = try c.decodeIfPresent(QualityDrawingRefDto.self, forKey: .drawing)
            ?? QualityDrawingRefDto(id: id, name: try c.decodeIfPresent(String.self, forKey: .name) ?? "樓層")
        taskCount = try c.decodeIfPresent(Int.self, forKey: .taskCount)
            ?? c.decodeIfPresent(Int.self, forKey: .spaceCount)
        taskCountByStatus = try c.decodeIfPresent(QualityDrawingTaskCountByStatusDto.self, forKey: .taskCountByStatus)
    }
}

struct QualityDrawingListResponseDto: Decodable, Sendable {
    let data: [QualityDrawingListItemDto]
    let pagination: PaginationDto

    enum CodingKeys: String, CodingKey {
        case data, pagination, meta
    }

    init(data: [QualityDrawingListItemDto], pagination: PaginationDto) {
        self.data = data
        self.pagination = pagination
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        data = try c.decode([QualityDrawingListItemDto].self, forKey: .data)
        pagination = try c.decodeIfPresent(PaginationDto.self, forKey: .pagination)
            ?? c.decodeIfPresent(PaginationDto.self, forKey: .meta)
            ?? PaginationDto(page: 1, limit: data.count, total: data.count)
    }
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

    enum CodingKeys: String, CodingKey {
        case name, description, categoryId, groupId, roomId, executorId, executorType, reviewerId, priority, dueDate
    }
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
        case name, description, priority, status, dueAt, categoryId, reviewerId
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
                try c.encode(dueDate, forKey: .dueAt)
            } else {
                try c.encodeNil(forKey: .dueAt)
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

    enum CodingKeys: String, CodingKey {
        case id, username, displayName, name, email
    }

    init(id: String, username: String?, displayName: String?) {
        self.id = id
        self.username = username
        self.displayName = displayName
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        username = try c.decodeIfPresent(String.self, forKey: .username) ?? c.decodeIfPresent(String.self, forKey: .email)
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName) ?? c.decodeIfPresent(String.self, forKey: .name)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encodeIfPresent(username, forKey: .username)
        try c.encodeIfPresent(displayName, forKey: .displayName)
    }
}

struct ProjectMemberDto: Codable, Sendable, Identifiable {
    let id: String
    let memberCategory: String?
    let user: ProjectMemberUserDto

    enum CodingKeys: String, CodingKey {
        case id, userId, memberCategory, category, role, user
    }

    init(id: String, memberCategory: String?, user: ProjectMemberUserDto) {
        self.id = id
        self.memberCategory = memberCategory
        self.user = user
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let user = try c.decode(ProjectMemberUserDto.self, forKey: .user)
        self.user = user
        id = try c.decodeIfPresent(String.self, forKey: .id)
            ?? c.decodeIfPresent(String.self, forKey: .userId)
            ?? user.id
        memberCategory = try c.decodeIfPresent(String.self, forKey: .memberCategory)
            ?? c.decodeIfPresent(String.self, forKey: .category)
            ?? c.decodeIfPresent(String.self, forKey: .role)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encodeIfPresent(memberCategory, forKey: .memberCategory)
        try c.encode(user, forKey: .user)
    }
}

struct ProjectMemberListResponseDto: Decodable, Sendable {
    let data: [ProjectMemberDto]
    let pagination: PaginationDto

    enum CodingKeys: String, CodingKey {
        case data, pagination, meta
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        data = try c.decode([ProjectMemberDto].self, forKey: .data)
        pagination = try c.decodeIfPresent(PaginationDto.self, forKey: .pagination)
            ?? c.decodeIfPresent(PaginationDto.self, forKey: .meta)
            ?? PaginationDto(page: 1, limit: data.count, total: data.count)
    }
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
