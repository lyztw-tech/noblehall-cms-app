import Foundation

nonisolated struct NotificationDto: Decodable, Sendable, Identifiable, Hashable {
    let id: String
    let type: String
    let title: String
    let body: String?
    let link: String?
    let readAt: Date?
    let projectId: String?
    let projectName: String?
    let projectCode: String?
    let createdAt: Date

    var isUnread: Bool { readAt == nil }

    enum CodingKeys: String, CodingKey {
        case id, type, eventType, title, body, link, linkMobile, linkWeb, readAt
        case projectId, projectName, projectCode, createdAt
    }

    init(
        id: String,
        type: String,
        title: String,
        body: String?,
        link: String?,
        readAt: Date?,
        projectId: String?,
        projectName: String?,
        projectCode: String?,
        createdAt: Date
    ) {
        self.id = id
        self.type = type
        self.title = title
        self.body = body
        self.link = link
        self.readAt = readAt
        self.projectId = projectId
        self.projectName = projectName
        self.projectCode = projectCode
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let projectId = try c.decodeIfPresent(String.self, forKey: .projectId)
        id = try c.decode(String.self, forKey: .id)
        type = try c.decodeIfPresent(String.self, forKey: .type)
            ?? c.decodeIfPresent(String.self, forKey: .eventType)
            ?? "notification"
        title = try c.decode(String.self, forKey: .title)
        body = try c.decodeIfPresent(String.self, forKey: .body)
        link = try c.decodeIfPresent(String.self, forKey: .link)
            ?? c.decodeIfPresent(String.self, forKey: .linkMobile)
            ?? c.decodeIfPresent(String.self, forKey: .linkWeb)
        readAt = try c.decodeIfPresent(Date.self, forKey: .readAt)
        self.projectId = projectId
        projectName = try c.decodeIfPresent(String.self, forKey: .projectName)
        projectCode = try c.decodeIfPresent(String.self, forKey: .projectCode) ?? projectId
        createdAt = try c.decode(Date.self, forKey: .createdAt)
    }
}

nonisolated struct NotificationListDto: Decodable, Sendable {
    let data: [NotificationDto]
    let pagination: NotificationPaginationDto

    enum CodingKeys: String, CodingKey {
        case data, pagination, meta
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        data = try c.decode([NotificationDto].self, forKey: .data)
        pagination = try c.decodeIfPresent(NotificationPaginationDto.self, forKey: .pagination)
            ?? c.decodeIfPresent(NotificationPaginationDto.self, forKey: .meta)
            ?? NotificationPaginationDto(page: 1, limit: data.count, total: data.count, totalAll: nil, totalPages: 1)
    }
}

nonisolated struct NotificationPaginationDto: Codable, Sendable {
    let page: Int
    let limit: Int
    let total: Int
    let totalAll: Int?
    let totalPages: Int

    init(page: Int, limit: Int, total: Int, totalAll: Int?, totalPages: Int? = nil) {
        self.page = page
        self.limit = limit
        self.total = total
        self.totalAll = totalAll
        self.totalPages = totalPages ?? max(1, Int(ceil(Double(total) / Double(max(1, limit)))))
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let page = try c.decodeIfPresent(Int.self, forKey: .page) ?? 1
        let limit = try c.decodeIfPresent(Int.self, forKey: .limit) ?? 20
        let total = try c.decodeIfPresent(Int.self, forKey: .total) ?? 0
        let totalAll = try c.decodeIfPresent(Int.self, forKey: .totalAll)
        let totalPages = try c.decodeIfPresent(Int.self, forKey: .totalPages)
        self.init(page: page, limit: limit, total: total, totalAll: totalAll, totalPages: totalPages)
    }
}

extension NotificationDto {
    func markedRead(at date: Date = Date()) -> NotificationDto {
        NotificationDto(
            id: id,
            type: type,
            title: title,
            body: body,
            link: link,
            readAt: date,
            projectId: projectId,
            projectName: projectName,
            projectCode: projectCode,
            createdAt: createdAt
        )
    }
}

nonisolated struct UnreadCountDto: Codable, Sendable {
    let count: Int
}

nonisolated struct MarkAllReadResponseDto: Decodable, Sendable {
    let ok: Bool
    let count: Int

    enum CodingKeys: String, CodingKey {
        case ok, count, updatedCount
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        ok = try c.decodeIfPresent(Bool.self, forKey: .ok) ?? true
        count = try c.decodeIfPresent(Int.self, forKey: .count)
            ?? c.decodeIfPresent(Int.self, forKey: .updatedCount)
            ?? 0
    }
}
