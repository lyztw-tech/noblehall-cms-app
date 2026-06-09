import Foundation

enum QualityTaskAPI: Sendable {
    private struct QualityTaskFloorPlanDto: Decodable {
        let id: String
        let name: String
        let attachmentId: String?
        let groups: [ConstructionFloorDetailDto.Group]?
        let spaces: [ConstructionFloorDetailDto.Space]
    }

    private struct ConstructionFloorDetailDto: Decodable {
        struct Group: Decodable {
            let id: String
            let name: String
        }

        struct Space: Decodable {
            let id: String
            let groupId: String?
            let name: String
            let posX: Double?
            let posY: Double?
        }

        let spaces: [Space]
    }

    private struct ConstructionCreateTaskBody: Encodable {
        let name: String
        let description: String?
        let categoryId: String?
        let floorId: String
        let groupId: String?
        let spaceId: String
        let reviewerId: String?
        let executorId: String?
        let dueAt: String?
    }

    private static func constructionStatus(_ status: String) -> String {
        switch QualityTaskEditEligibility.normalizedStatus(status) {
        case "pending_assignment": return "unassigned"
        case "director_check": return "pending_owner_confirmation"
        case "in_review": return "pending_review"
        case "rejected": return "returned"
        case "approved": return "completed"
        default: return status
        }
    }

    private static func countsByFloor(from tasks: [QualityTaskListItemDto]) -> [String: QualityDrawingTaskCountByStatusDto] {
        var pending: [String: Int] = [:]
        var inProgress: [String: Int] = [:]
        var director: [String: Int] = [:]
        var review: [String: Int] = [:]
        var approved: [String: Int] = [:]

        for task in tasks {
            guard let floorId = task.qualityDrawing?.id, !floorId.isEmpty else { continue }
            switch QualityTaskEditEligibility.normalizedStatus(task.status) {
            case "pending_assignment":
                pending[floorId, default: 0] += 1
            case "in_progress", "rejected":
                inProgress[floorId, default: 0] += 1
            case "director_check":
                director[floorId, default: 0] += 1
            case "in_review":
                review[floorId, default: 0] += 1
            case "approved":
                approved[floorId, default: 0] += 1
            default:
                break
            }
        }

        let floorIds = Set(pending.keys)
            .union(inProgress.keys)
            .union(director.keys)
            .union(review.keys)
            .union(approved.keys)

        var result: [String: QualityDrawingTaskCountByStatusDto] = [:]
        for floorId in floorIds {
            result[floorId] = QualityDrawingTaskCountByStatusDto(
                pendingAssignmentCount: pending[floorId, default: 0],
                inProgressCount: inProgress[floorId, default: 0],
                directorCheckCount: director[floorId, default: 0],
                inReviewCount: review[floorId, default: 0],
                approvedCount: approved[floorId, default: 0]
            )
        }
        return result
    }

    private static func totalTaskCount(_ counts: QualityDrawingTaskCountByStatusDto) -> Int {
        counts.pendingAssignmentCount
            + counts.inProgressCount
            + counts.directorCheckCount
            + counts.inReviewCount
            + counts.approvedCount
    }

    private static func uploadAttachments(
        projectId: String,
        category: String,
        attachments: [(data: Data, filename: String, mimeType: String)]
    ) async throws -> [String] {
        var ids: [String] = []
        for item in attachments {
            let response: APIDataEnvelope<UploadedFileDto> = try await APIClient.shared.sendMultipart(
                .POST,
                path: "files/upload",
                queryItems: nil,
                fields: [
                    "projectId": projectId,
                    "category": category,
                    "fileName": item.filename,
                ],
                files: [MultipartFilePart(fieldName: "file", filename: item.filename, mimeType: item.mimeType, data: item.data)]
            )
            ids.append(response.data.id)
        }
        return ids
    }

    /// `executorId` 為 `nil` 時與 Web 任務管理「總表」相同：列出專案內可見之全部品質任務。  
    /// 有值時僅篩 `quality_task.executor_id` 等於該 UUID（**不含**「執行對象為群組」的任務，因 DB 存的是群組 id）。
    static func listProjectTasks(
        projectCode: String,
        executorIds: [String]? = nil,
        qualityDrawingId: String? = nil,
        statuses: [String]? = nil,
        priorities: [String]? = nil,
        groupIds: [String]? = nil,
        roomIds: [String]? = nil,
        categoryIds: [String]? = nil,
        reviewerIds: [String]? = nil,
        search: String? = nil,
        startDate: String? = nil,
        endDate: String? = nil,
        dueDateFrom: String? = nil,
        dueDateTo: String? = nil,
        onlyMyTasks: Bool? = nil,
        page: Int = 1,
        limit: Int = 100
    ) async throws -> QualityTaskListResponseDto {
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        if let executorIds {
            for e in executorIds where !e.isEmpty {
                queryItems.append(URLQueryItem(name: "executorId", value: e))
            }
        }
        if let qualityDrawingId, !qualityDrawingId.isEmpty {
            queryItems.append(URLQueryItem(name: "qualityDrawingId", value: qualityDrawingId))
        }
        if let search, !search.isEmpty {
            queryItems.append(URLQueryItem(name: "q", value: search))
        }
        if let statuses {
            for status in statuses where !status.isEmpty {
                queryItems.append(URLQueryItem(name: "status", value: constructionStatus(status)))
            }
        }
        if let priorities {
            for p in priorities where !p.isEmpty {
                queryItems.append(URLQueryItem(name: "priority", value: p))
            }
        }
        if let groupIds {
            for g in groupIds where !g.isEmpty {
                queryItems.append(URLQueryItem(name: "groupId", value: g))
            }
        }
        if let roomIds {
            for r in roomIds where !r.isEmpty {
                queryItems.append(URLQueryItem(name: "roomId", value: r))
            }
        }
        if let categoryIds {
            for c in categoryIds where !c.isEmpty {
                queryItems.append(URLQueryItem(name: "categoryId", value: c))
            }
        }
        if let reviewerIds {
            for r in reviewerIds where !r.isEmpty {
                queryItems.append(URLQueryItem(name: "reviewerId", value: r))
            }
        }
        if let startDate, !startDate.isEmpty {
            queryItems.append(URLQueryItem(name: "startDate", value: startDate))
        }
        if let endDate, !endDate.isEmpty {
            queryItems.append(URLQueryItem(name: "endDate", value: endDate))
        }
        if let dueDateFrom, !dueDateFrom.isEmpty {
            queryItems.append(URLQueryItem(name: "dueDateFrom", value: dueDateFrom))
        }
        if let dueDateTo, !dueDateTo.isEmpty {
            queryItems.append(URLQueryItem(name: "dueDateTo", value: dueDateTo))
        }
        if let onlyMyTasks {
            queryItems.append(URLQueryItem(name: "onlyMyTasks", value: onlyMyTasks ? "true" : "false"))
        }
        return try await APIClient.shared.send(
            .GET,
            path: "projects/\(projectCode)/quality-tasks",
            queryItems: queryItems
        )
    }

    static func allProjectTasks(
        projectCode: String,
        filter: TaskManagementFilterStore? = nil,
        executorIds: [String]? = nil,
        qualityDrawingId: String? = nil,
        statuses: [String]? = nil,
        onlyMyTasks: Bool? = nil
    ) async throws -> [QualityTaskListItemDto] {
        let pageLimit = 100
        var page = 1
        var all: [QualityTaskListItemDto] = []
        let drawingId = qualityDrawingId ?? filter?.qualityDrawingId
        let statusList: [String]? = {
            if let statuses, !statuses.isEmpty { return statuses }
            if let filter, !filter.statuses.isEmpty { return filter.statuses }
            return nil
        }()
        let resolvedExecutorIds: [String]? = {
            if let executorIds, !executorIds.isEmpty { return executorIds }
            if let filter, !filter.executorIds.isEmpty { return filter.executorIds }
            return nil
        }()
        let search = filter?.search.trimmingCharacters(in: .whitespacesAndNewlines)
        let fmt = TaskManagementFilterStore.isoDateOnlyFormatter
        while true {
            let res = try await listProjectTasks(
                projectCode: projectCode,
                executorIds: resolvedExecutorIds,
                qualityDrawingId: drawingId,
                statuses: statusList,
                priorities: filter?.priorities.isEmpty == false ? filter?.priorities : nil,
                groupIds: filter?.groupIds.isEmpty == false ? filter?.groupIds : nil,
                roomIds: filter?.roomIds.isEmpty == false ? filter?.roomIds : nil,
                categoryIds: filter?.categoryIds.isEmpty == false ? filter?.categoryIds : nil,
                reviewerIds: filter?.reviewerIds.isEmpty == false ? filter?.reviewerIds : nil,
                search: (search?.isEmpty == false) ? search : nil,
                startDate: filter?.createdFrom.map { fmt.string(from: $0) },
                endDate: filter?.createdTo.map { fmt.string(from: $0) },
                dueDateFrom: filter?.dueFrom.map { fmt.string(from: $0) },
                dueDateTo: filter?.dueTo.map { fmt.string(from: $0) },
                onlyMyTasks: onlyMyTasks,
                page: page,
                limit: pageLimit
            )
            all.append(contentsOf: res.data)
            if page >= res.pagination.totalPages { break }
            page += 1
        }
        if let drawingId, !drawingId.isEmpty {
            return all.filter { $0.qualityDrawing?.id == drawingId }
        }
        return all
    }

    static func taskDetail(projectCode: String, taskId: String) async throws -> QualityTaskDetailResponseDto {
        let taskEnvelope: APIDataEnvelope<QualityTaskDto> = try await APIClient.shared.send(
            .GET,
            path: "projects/\(projectCode)/quality-tasks/\(taskId)"
        )
        let records = (try? await listTaskRecords(projectCode: projectCode, taskId: taskId)) ?? []
        let submission = records.isEmpty ? nil : QualityTaskSubmissionDto(id: nil, executions: records)
        let ledger = records.map { record in
            TaskLedgerEntryDto(
                id: record.id,
                kind: .execution,
                occurredAt: record.createdAt ?? record.executedAt ?? Date(),
                submissionId: record.submissionId,
                round: nil,
                actor: TaskLedgerActorDto(
                    id: record.executor?.id ?? "",
                    username: record.executor?.username,
                    displayName: record.executor?.displayName
                ),
                body: record.executionReply,
                result: nil,
                attachments: record.attachments
            )
        }
        return QualityTaskDetailResponseDto(task: taskEnvelope.data, latestSubmission: submission, viewer: nil, ledger: ledger)
    }

    static func listTaskRecords(projectCode: String, taskId: String) async throws -> [ExecutionRecordDto] {
        let envelope: APIDataEnvelope<[ExecutionRecordDto]> = try await APIClient.shared.send(
            .GET,
            path: "projects/\(projectCode)/quality-tasks/\(taskId)/records"
        )
        return envelope.data
    }

    static func updateTask(
        projectCode: String,
        qualityDrawingId: String,
        taskId: String,
        body: UpdateQualityTaskBody
    ) async throws -> UpdateQualityTaskResponseDto {
        let envelope: APIDataEnvelope<UpdateQualityTaskResponseDto> = try await APIClient.shared.send(
            .PATCH,
            path: "projects/\(projectCode)/quality-tasks/\(taskId)",
            body: body
        )
        return envelope.data
    }

    static func drawingDetail(projectCode: String, qualityDrawingId: String) async throws -> QualityDrawingDetailDto {
        guard let floor = try await qualityTaskFloorPlan(projectCode: projectCode, qualityDrawingId: qualityDrawingId) else {
            throw APIRequestError.httpStatus(code: 404, body: "找不到此任務的平面圖資料")
        }
        return qualityDrawingDetail(from: floor)
    }

    static func roomPoints(projectCode: String, qualityDrawingId: String) async throws -> [QualityTaskRoomPointDto] {
        guard let floor = try await qualityTaskFloorPlan(projectCode: projectCode, qualityDrawingId: qualityDrawingId) else {
            throw APIRequestError.httpStatus(code: 404, body: "找不到此任務的空間資料")
        }
        return roomPoints(from: floor.spaces)
    }

    static func drawingGroups(projectCode: String, qualityDrawingId: String) async throws -> [ProjectGroupDto] {
        guard let floor = try await qualityTaskFloorPlan(projectCode: projectCode, qualityDrawingId: qualityDrawingId) else {
            throw APIRequestError.httpStatus(code: 404, body: "找不到此任務的群組資料")
        }
        return projectGroups(from: [floor])
    }

    private static func qualityTaskFloorPlan(projectCode: String, qualityDrawingId: String) async throws -> QualityTaskFloorPlanDto? {
        let envelope: APIDataEnvelope<[QualityTaskFloorPlanDto]> = try await APIClient.shared.send(
            .GET,
            path: "projects/\(projectCode)/quality-tasks/floor-plans"
        )
        return envelope.data.first { $0.id == qualityDrawingId }
    }

    private static func qualityDrawingDetail(from floor: QualityTaskFloorPlanDto) -> QualityDrawingDetailDto {
        QualityDrawingDetailDto(
            id: floor.id,
            drawing: DrawingDetailInnerDto(
                id: floor.id,
                name: floor.name,
                file: floor.attachmentId.map {
                    DrawingFileDto(
                        id: $0,
                        originalFilename: nil,
                        url: "files/\($0)",
                        thumbnailUrl: nil
                    )
                }
            )
        )
    }

    private static func roomPoints(from spaces: [ConstructionFloorDetailDto.Space]) -> [QualityTaskRoomPointDto] {
        spaces.compactMap {
            guard let posX = $0.posX, let posY = $0.posY else { return nil }
            return QualityTaskRoomPointDto(
                id: $0.id,
                groupId: $0.groupId,
                x: posX,
                y: posY,
                name: $0.name,
                taskCount: nil,
                incompleteTaskCount: nil
            )
        }
    }

    static func listQualityDrawings(
        projectCode: String,
        page: Int = 1,
        limit: Int = 100,
        sort: String = "name",
        order: String = "asc"
    ) async throws -> QualityDrawingListResponseDto {
        let envelope: APIDataEnvelope<[QualityTaskFloorPlanDto]> = try await APIClient.shared.send(
            .GET,
            path: "projects/\(projectCode)/quality-tasks/floor-plans"
        )
        let sorted = envelope.data.sorted { lhs, rhs in
            let comparison = lhs.name.localizedStandardCompare(rhs.name)
            return order.lowercased() == "desc" ? comparison == .orderedDescending : comparison == .orderedAscending
        }
        let safeLimit = max(1, limit)
        let safePage = max(1, page)
        let start = min((safePage - 1) * safeLimit, sorted.count)
        let end = min(start + safeLimit, sorted.count)
        let pageItems = Array(sorted[start..<end])
        return QualityDrawingListResponseDto(
            data: pageItems.map { floor in
                QualityDrawingListItemDto(
                    id: floor.id,
                    drawing: QualityDrawingRefDto(id: floor.id, name: floor.name),
                    taskCount: floor.spaces.count,
                    taskCountByStatus: nil
                )
            },
            pagination: PaginationDto(page: safePage, limit: safeLimit, total: sorted.count)
        )
    }

    static func allQualityDrawings(projectCode: String) async throws -> [QualityDrawingListItemDto] {
        let pageLimit = 100
        var page = 1
        var all: [QualityDrawingListItemDto] = []
        while true {
            let res = try await listQualityDrawings(
                projectCode: projectCode,
                page: page,
                limit: pageLimit
            )
            all.append(contentsOf: res.data)
            if page >= res.pagination.totalPages { break }
            page += 1
        }
        let tasks = (try? await allProjectTasks(projectCode: projectCode)) ?? []
        let counts = countsByFloor(from: tasks)
        return all.map { floor in
            let floorCounts = counts[floor.id] ?? .zero
            return QualityDrawingListItemDto(
                id: floor.id,
                drawing: floor.drawing,
                taskCount: totalTaskCount(floorCounts),
                taskCountByStatus: floorCounts
            )
        }
    }

    static func createTask(
        projectCode: String,
        qualityDrawingId: String,
        body: CreateQualityTaskBody
    ) async throws -> CreateQualityTaskResponseDto {
        let envelope: APIDataEnvelope<CreateQualityTaskResponseDto> = try await APIClient.shared.send(
            .POST,
            path: "projects/\(projectCode)/quality-tasks",
            body: ConstructionCreateTaskBody(
                name: body.name,
                description: body.description,
                categoryId: body.categoryId,
                floorId: qualityDrawingId,
                groupId: body.groupId,
                spaceId: body.roomId ?? "",
                reviewerId: body.reviewerId.isEmpty ? nil : body.reviewerId,
                executorId: body.executorId,
                dueAt: body.dueDate
            )
        )
        return envelope.data
    }

    static func uploadTaskAttachments(
        projectCode: String,
        qualityDrawingId: String,
        taskId: String,
        attachments: [(data: Data, filename: String, mimeType: String)]
    ) async throws {
        let ids = try await uploadAttachments(projectId: projectCode, category: "quality", attachments: attachments)
        guard !ids.isEmpty else { return }
        struct AttachmentPatchBody: Encodable { let attachmentIds: [String] }
        try await APIClient.shared.sendVoid(
            .PATCH,
            path: "projects/\(projectCode)/quality-tasks/\(taskId)",
            body: AttachmentPatchBody(attachmentIds: ids)
        )
    }

    static func listProjectMembers(
        projectCode: String,
        page: Int = 1,
        limit: Int = 100
    ) async throws -> ProjectMemberListResponseDto {
        try await APIClient.shared.send(
            .GET,
            path: "projects/\(projectCode)/quality-tasks/assignment-members",
            queryItems: [
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "limit", value: String(limit)),
            ]
        )
    }

    /// 分頁拉齊專案成員（後端 `limit` 上限 100）。
    static func allProjectMembers(projectCode: String) async throws -> [ProjectMemberDto] {
        let pageLimit = 100
        var page = 1
        var all: [ProjectMemberDto] = []
        while true {
            let res = try await listProjectMembers(
                projectCode: projectCode,
                page: page,
                limit: pageLimit
            )
            all.append(contentsOf: res.data)
            if page >= res.pagination.totalPages { break }
            page += 1
        }
        return all
    }

    static func listProjectGroups(projectCode: String) async throws -> ProjectGroupListResponseDto {
        let envelope: APIDataEnvelope<[QualityTaskFloorPlanDto]> = try await APIClient.shared.send(
            .GET,
            path: "projects/\(projectCode)/quality-tasks/floor-plans"
        )
        return ProjectGroupListResponseDto(data: projectGroups(from: envelope.data))
    }

    private static func projectGroups(from floors: [QualityTaskFloorPlanDto]) -> [ProjectGroupDto] {
        var seen: Set<String> = []
        var groups: [ProjectGroupDto] = []
        for group in floors.flatMap({ $0.groups ?? [] }) where !seen.contains(group.id) {
            seen.insert(group.id)
            groups.append(ProjectGroupDto(id: group.id, name: group.name, ownerId: nil))
        }
        return groups.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    static func categoryOptions(projectId: String) async throws -> DropdownFieldDto {
        let envelope: APIDataEnvelope<[CategoryRefDto]> = try await APIClient.shared.send(
            .GET,
            path: "projects/\(projectId)/categories",
            queryItems: [
                URLQueryItem(name: "type", value: "quality_task"),
            ]
        )
        return DropdownFieldDto(
            businessType: "quality_task",
            fieldName: "category",
            options: envelope.data.map { DropdownOptionItemDto(id: $0.id, value: $0.value) }
        )
    }

    static func createExecution(
        projectCode: String,
        qualityDrawingId: String,
        taskId: String,
        executionReply: String?,
        attachments: [(data: Data, filename: String, mimeType: String)]
    ) async throws -> CreateExecutionResponseDto {
        let attachmentIds = try await uploadAttachments(projectId: projectCode, category: "quality_record", attachments: attachments)
        struct CreateRecordBody: Encodable {
            let content: String
            let attachmentIds: [String]
        }
        let envelope: APIDataEnvelope<ExecutionRecordDto> = try await APIClient.shared.send(
            .POST,
            path: "projects/\(projectCode)/quality-tasks/\(taskId)/records",
            body: CreateRecordBody(
                content: executionReply?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false ? executionReply! : "已新增執行紀錄",
                attachmentIds: attachmentIds
            )
        )
        return CreateExecutionResponseDto(id: envelope.data.id, uuid: envelope.data.id, uploadWarnings: nil)
    }

    static func submitExecution(
        projectCode: String,
        qualityDrawingId: String,
        taskId: String,
        body: SubmitExecutionBody = .savedExecutionsOnly
    ) async throws -> QualityTaskSubmissionDto {
        let envelope: APIDataEnvelope<QualityTaskDto> = try await APIClient.shared.send(
            .POST,
            path: "projects/\(projectCode)/quality-tasks/\(taskId)/submit",
            body: EmptyRequestBody()
        )
        _ = envelope.data
        return QualityTaskSubmissionDto(id: nil, executions: nil)
    }

    static func updateExecution(
        projectCode: String,
        qualityDrawingId: String,
        taskId: String,
        executionId: String,
        body: UpdateExecutionBody
    ) async throws {
        struct UpdateRecordBody: Encodable {
            let content: String?
            let attachmentIds: [String]?
        }
        let path = "projects/\(projectCode)/quality-tasks/\(taskId)/records/\(executionId)"
        try await APIClient.shared.sendVoid(
            .PATCH,
            path: path,
            body: UpdateRecordBody(content: body.executionReply, attachmentIds: body.attachmentIds)
        )
    }

    /// 上傳執行紀錄附件並回傳檔案 id；更新時併入 `UpdateExecutionBody.attachmentIds` 保留集。
    static func uploadExecutionAttachmentIds(
        projectCode: String,
        attachments: [(data: Data, filename: String, mimeType: String)]
    ) async throws -> [String] {
        try await uploadAttachments(projectId: projectCode, category: "quality_record", attachments: attachments)
    }

    /// 為既有執行紀錄追加附件（multipart `attachments`）；與建立時相同之每筆上限由後端檢核。
    static func uploadExecutionAttachments(
        projectCode: String,
        qualityDrawingId: String,
        taskId: String,
        executionId: String,
        attachments: [(data: Data, filename: String, mimeType: String)]
    ) async throws -> UploadExecutionAttachmentsResponseDto {
        _ = try await uploadAttachments(projectId: projectCode, category: "quality_record", attachments: attachments)
        return UploadExecutionAttachmentsResponseDto(success: true, message: nil)
    }

    static func deleteExecution(
        projectCode: String,
        qualityDrawingId: String,
        taskId: String,
        executionId: String
    ) async throws {
        // Construction Dashboard does not expose record deletion in the MVP API.
    }

    private static func reviewResult(_ result: QualityTaskReviewResult) -> String {
        switch result {
        case .approved: return "pass"
        case .rejected: return "return"
        }
    }

    private static func ownerConfirm(
        projectCode: String,
        taskId: String,
        body: ReviewSubmissionBody
    ) async throws -> QualityTaskSubmissionDto {
        struct ReviewBody: Encodable {
            let result: String
            let content: String
            let attachmentIds: [String]
        }
        let envelope: APIDataEnvelope<QualityTaskDto> = try await APIClient.shared.send(
            .POST,
            path: "projects/\(projectCode)/quality-tasks/\(taskId)/owner-confirm",
            body: ReviewBody(result: reviewResult(body.reviewResult), content: body.reviewComment ?? "", attachmentIds: [])
        )
        _ = envelope.data
        return QualityTaskSubmissionDto(id: nil, executions: nil)
    }

    private static func review(
        projectCode: String,
        taskId: String,
        body: ReviewSubmissionBody
    ) async throws -> QualityTaskSubmissionDto {
        struct ReviewBody: Encodable {
            let result: String
            let content: String
            let attachmentIds: [String]
        }
        let envelope: APIDataEnvelope<QualityTaskDto> = try await APIClient.shared.send(
            .POST,
            path: "projects/\(projectCode)/quality-tasks/\(taskId)/review",
            body: ReviewBody(result: reviewResult(body.reviewResult), content: body.reviewComment ?? "", attachmentIds: [])
        )
        _ = envelope.data
        return QualityTaskSubmissionDto(id: nil, executions: nil)
    }

    static func directorReviewSubmission(
        projectCode: String,
        qualityDrawingId: String,
        taskId: String,
        submissionId: String,
        body: ReviewSubmissionBody
    ) async throws -> QualityTaskSubmissionDto {
        try await ownerConfirm(projectCode: projectCode, taskId: taskId, body: body)
    }

    static func reviewSubmission(
        projectCode: String,
        qualityDrawingId: String,
        taskId: String,
        submissionId: String,
        body: ReviewSubmissionBody
    ) async throws -> QualityTaskSubmissionDto {
        try await review(projectCode: projectCode, taskId: taskId, body: body)
    }

    static func uploadDirectorReviewAttachments(
        projectCode: String,
        qualityDrawingId: String,
        taskId: String,
        submissionId: String,
        attachments: [(data: Data, filename: String, mimeType: String)]
    ) async throws -> UploadReviewAttachmentsResponseDto {
        _ = try await uploadAttachments(projectId: projectCode, category: "quality_record", attachments: attachments)
        return UploadReviewAttachmentsResponseDto(success: true, message: nil)
    }

    static func uploadReviewAttachments(
        projectCode: String,
        qualityDrawingId: String,
        taskId: String,
        submissionId: String,
        attachments: [(data: Data, filename: String, mimeType: String)]
    ) async throws -> UploadReviewAttachmentsResponseDto {
        _ = try await uploadAttachments(projectId: projectCode, category: "quality_record", attachments: attachments)
        return UploadReviewAttachmentsResponseDto(success: true, message: nil)
    }
}
