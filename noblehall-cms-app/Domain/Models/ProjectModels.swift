import Foundation

struct PaginationDto: Codable, Sendable {
    let page: Int
    let limit: Int
    let total: Int
    let totalAll: Int?
    let totalPages: Int
}

struct ProjectListItemDto: Codable, Sendable, Identifiable {
    let projectId: String?
    let name: String
    let code: String
    let status: String
    let address: String?

    var id: String { projectId ?? code }

    enum CodingKeys: String, CodingKey {
        case projectId = "id"
        case name, code, status, address
    }
}

struct ProjectDetailDto: Codable, Sendable {
    let id: String
    let code: String
    let name: String
}

struct ProjectListResponseDto: Codable, Sendable {
    let data: [ProjectListItemDto]
    let pagination: PaginationDto
}
