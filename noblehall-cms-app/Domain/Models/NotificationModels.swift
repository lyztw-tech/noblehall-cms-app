import Foundation

struct NotificationDto: Codable, Sendable, Identifiable, Hashable {
    let id: String
    let type: String
    let title: String
    let body: String?
    let link: String?
    let readAt: Date?
    let spaceId: String?
    let projectId: String?
    let projectName: String?
    let projectCode: String?
    let createdAt: Date

    var isUnread: Bool { readAt == nil }
}

struct NotificationListDto: Codable, Sendable {
    let data: [NotificationDto]
    let pagination: NotificationPaginationDto
}

struct NotificationPaginationDto: Codable, Sendable {
    let page: Int
    let limit: Int
    let total: Int
    let totalAll: Int?
    let totalPages: Int
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
            spaceId: spaceId,
            projectId: projectId,
            projectName: projectName,
            projectCode: projectCode,
            createdAt: createdAt
        )
    }
}

struct UnreadCountDto: Codable, Sendable {
    let count: Int
}

struct MarkAllReadResponseDto: Codable, Sendable {
    let ok: Bool
    let count: Int
}
