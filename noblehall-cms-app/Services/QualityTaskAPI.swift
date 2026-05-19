import Foundation

enum QualityTaskAPI: Sendable {
    /// `executorId` 為 `nil` 時與 Web 任務管理「總表」相同：列出專案內可見之全部品質任務。  
    /// 有值時僅篩 `quality_task.executor_id` 等於該 UUID（**不含**「執行對象為群組」的任務，因 DB 存的是群組 id）。
    static func listProjectTasks(
        projectCode: String,
        spaceId: String,
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
            queryItems.append(URLQueryItem(name: "search", value: search))
        }
        if let statuses {
            for status in statuses where !status.isEmpty {
                queryItems.append(URLQueryItem(name: "status", value: status))
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
        return try await APIClient.shared.send(
            .GET,
            path: "projects/\(projectCode)/quality-tasks",
            queryItems: queryItems,
            spaceId: spaceId
        )
    }

    static func allProjectTasks(
        projectCode: String,
        spaceId: String,
        filter: TaskManagementFilterStore? = nil,
        executorIds: [String]? = nil,
        qualityDrawingId: String? = nil,
        statuses: [String]? = nil
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
                spaceId: spaceId,
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
                page: page,
                limit: pageLimit
            )
            all.append(contentsOf: res.data)
            if page >= res.pagination.totalPages { break }
            page += 1
        }
        return all
    }

    static func taskDetail(projectCode: String, taskId: String, spaceId: String) async throws -> QualityTaskDetailResponseDto {
        try await APIClient.shared.send(
            .GET,
            path: "projects/\(projectCode)/quality-tasks/\(taskId)",
            spaceId: spaceId
        )
    }

    static func updateTask(
        projectCode: String,
        qualityDrawingId: String,
        taskId: String,
        body: UpdateQualityTaskBody,
        spaceId: String
    ) async throws -> UpdateQualityTaskResponseDto {
        try await APIClient.shared.send(
            .PATCH,
            path: "projects/\(projectCode)/quality-drawings/\(qualityDrawingId)/tasks/\(taskId)",
            body: body,
            spaceId: spaceId
        )
    }

    static func drawingDetail(projectCode: String, qualityDrawingId: String, spaceId: String) async throws -> QualityDrawingDetailDto {
        try await APIClient.shared.send(
            .GET,
            path: "projects/\(projectCode)/quality-drawings/\(qualityDrawingId)",
            spaceId: spaceId
        )
    }

    static func roomPoints(projectCode: String, qualityDrawingId: String, spaceId: String) async throws -> [QualityTaskRoomPointDto] {
        try await APIClient.shared.send(
            .GET,
            path: "projects/\(projectCode)/quality-drawings/\(qualityDrawingId)/tasks/points",
            spaceId: spaceId
        )
    }

    static func listQualityDrawings(
        projectCode: String,
        spaceId: String,
        page: Int = 1,
        limit: Int = 100,
        sort: String = "name",
        order: String = "asc"
    ) async throws -> QualityDrawingListResponseDto {
        try await APIClient.shared.send(
            .GET,
            path: "projects/\(projectCode)/quality-drawings",
            queryItems: [
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "limit", value: String(limit)),
                URLQueryItem(name: "sort", value: sort),
                URLQueryItem(name: "order", value: order),
            ],
            spaceId: spaceId
        )
    }

    static func allQualityDrawings(projectCode: String, spaceId: String) async throws -> [QualityDrawingListItemDto] {
        let pageLimit = 100
        var page = 1
        var all: [QualityDrawingListItemDto] = []
        while true {
            let res = try await listQualityDrawings(
                projectCode: projectCode,
                spaceId: spaceId,
                page: page,
                limit: pageLimit
            )
            all.append(contentsOf: res.data)
            if page >= res.pagination.totalPages { break }
            page += 1
        }
        return all
    }

    static func createTask(
        projectCode: String,
        qualityDrawingId: String,
        body: CreateQualityTaskBody,
        spaceId: String
    ) async throws -> CreateQualityTaskResponseDto {
        try await APIClient.shared.send(
            .POST,
            path: "projects/\(projectCode)/quality-drawings/\(qualityDrawingId)/tasks",
            body: body,
            spaceId: spaceId
        )
    }

    static func uploadTaskAttachments(
        projectCode: String,
        qualityDrawingId: String,
        taskId: String,
        attachments: [(data: Data, filename: String, mimeType: String)],
        spaceId: String
    ) async throws {
        let path = "projects/\(projectCode)/quality-drawings/\(qualityDrawingId)/tasks/\(taskId)/attachments"
        let fields: [String: String] = [:]
        let parts = attachments.map {
            MultipartFilePart(fieldName: "attachments", filename: $0.filename, mimeType: $0.mimeType, data: $0.data)
        }
        struct UploadAttachmentsResponseDto: Decodable { let success: Bool? }
        _ = try await APIClient.shared.sendMultipart(
            .POST,
            path: path,
            queryItems: nil,
            fields: fields,
            files: parts,
            spaceId: spaceId
        ) as UploadAttachmentsResponseDto
    }

    static func listProjectMembers(
        projectCode: String,
        spaceId: String,
        page: Int = 1,
        limit: Int = 100
    ) async throws -> ProjectMemberListResponseDto {
        try await APIClient.shared.send(
            .GET,
            path: "projects/\(projectCode)/members",
            queryItems: [
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "limit", value: String(limit)),
            ],
            spaceId: spaceId
        )
    }

    /// 分頁拉齊專案成員（後端 `limit` 上限 100）。
    static func allProjectMembers(projectCode: String, spaceId: String) async throws -> [ProjectMemberDto] {
        let pageLimit = 100
        var page = 1
        var all: [ProjectMemberDto] = []
        while true {
            let res = try await listProjectMembers(
                projectCode: projectCode,
                spaceId: spaceId,
                page: page,
                limit: pageLimit
            )
            all.append(contentsOf: res.data)
            if page >= res.pagination.totalPages { break }
            page += 1
        }
        return all
    }

    static func listProjectGroups(projectCode: String, spaceId: String) async throws -> ProjectGroupListResponseDto {
        try await APIClient.shared.send(
            .GET,
            path: "projects/\(projectCode)/groups",
            spaceId: spaceId
        )
    }

    static func categoryOptions(projectId: String, spaceId: String) async throws -> DropdownFieldDto {
        try await APIClient.shared.send(
            .GET,
            path: "dropdown-options",
            queryItems: [
                URLQueryItem(name: "businessType", value: "quality_task"),
                URLQueryItem(name: "fieldName", value: "category"),
                URLQueryItem(name: "projectId", value: projectId),
            ],
            spaceId: spaceId
        )
    }

    static func createExecution(
        projectCode: String,
        qualityDrawingId: String,
        taskId: String,
        executionReply: String?,
        attachments: [(data: Data, filename: String, mimeType: String)],
        spaceId: String
    ) async throws -> CreateExecutionResponseDto {
        let path = "projects/\(projectCode)/quality-drawings/\(qualityDrawingId)/tasks/\(taskId)/submissions/executions"
        if attachments.isEmpty {
            return try await APIClient.shared.send(
                .POST,
                path: path,
                body: CreateExecutionBody(executionReply: executionReply),
                spaceId: spaceId
            )
        }
        var fields: [String: String] = [:]
        if let r = executionReply?.trimmingCharacters(in: .whitespacesAndNewlines), !r.isEmpty {
            fields["executionReply"] = r
        }
        let parts = attachments.map {
            MultipartFilePart(fieldName: "attachments", filename: $0.filename, mimeType: $0.mimeType, data: $0.data)
        }
        return try await APIClient.shared.sendMultipart(
            .POST,
            path: path,
            queryItems: nil,
            fields: fields,
            files: parts,
            spaceId: spaceId
        )
    }

    static func updateExecution(
        projectCode: String,
        qualityDrawingId: String,
        taskId: String,
        executionId: String,
        body: UpdateExecutionBody,
        spaceId: String
    ) async throws {
        let path =
            "projects/\(projectCode)/quality-drawings/\(qualityDrawingId)/tasks/\(taskId)/submissions/executions/\(executionId)"
        try await APIClient.shared.sendVoid(
            .PATCH,
            path: path,
            body: body,
            spaceId: spaceId
        )
    }

    /// 為既有執行紀錄追加附件（multipart `attachments`）；與建立時相同之每筆上限由後端檢核。
    static func uploadExecutionAttachments(
        projectCode: String,
        qualityDrawingId: String,
        taskId: String,
        executionId: String,
        attachments: [(data: Data, filename: String, mimeType: String)],
        spaceId: String
    ) async throws -> UploadExecutionAttachmentsResponseDto {
        let path =
            "projects/\(projectCode)/quality-drawings/\(qualityDrawingId)/tasks/\(taskId)/submissions/executions/\(executionId)/attachments"
        let parts = attachments.map {
            MultipartFilePart(fieldName: "attachments", filename: $0.filename, mimeType: $0.mimeType, data: $0.data)
        }
        return try await APIClient.shared.sendMultipart(
            .POST,
            path: path,
            queryItems: nil,
            fields: [:],
            files: parts,
            spaceId: spaceId
        )
    }

    static func deleteExecution(
        projectCode: String,
        qualityDrawingId: String,
        taskId: String,
        executionId: String,
        spaceId: String
    ) async throws {
        let path =
            "projects/\(projectCode)/quality-drawings/\(qualityDrawingId)/tasks/\(taskId)/submissions/executions/\(executionId)"
        try await APIClient.shared.sendVoid(.DELETE, path: path, spaceId: spaceId)
    }
}
