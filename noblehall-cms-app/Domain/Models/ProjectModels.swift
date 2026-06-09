import Foundation

struct PaginationDto: Codable, Sendable {
    let page: Int
    let limit: Int
    let total: Int
    let totalAll: Int?
    let totalPages: Int

    init(page: Int, limit: Int, total: Int, totalAll: Int? = nil, totalPages: Int? = nil) {
        self.page = page
        self.limit = limit
        self.total = total
        self.totalAll = totalAll
        self.totalPages = totalPages ?? max(1, Int(ceil(Double(total) / Double(max(1, limit)))))
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let page = try c.decodeIfPresent(Int.self, forKey: .page) ?? 1
        let limit = try c.decodeIfPresent(Int.self, forKey: .limit) ?? 100
        let total = try c.decodeIfPresent(Int.self, forKey: .total) ?? 0
        let totalAll = try c.decodeIfPresent(Int.self, forKey: .totalAll)
        let totalPages = try c.decodeIfPresent(Int.self, forKey: .totalPages)
        self.init(page: page, limit: limit, total: total, totalAll: totalAll, totalPages: totalPages)
    }
}

struct ProjectListItemDto: Decodable, Sendable, Identifiable {
    let projectId: String?
    let name: String
    let code: String
    let status: String
    let address: String?

    var id: String { projectId ?? code }

    enum CodingKeys: String, CodingKey {
        case projectId = "id"
        case name, code, status, address, description
    }

    init(projectId: String?, name: String, code: String, status: String, address: String?) {
        self.projectId = projectId
        self.name = name
        self.code = code
        self.status = status
        self.address = address
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let projectId = try c.decodeIfPresent(String.self, forKey: .projectId)
        let code = try c.decodeIfPresent(String.self, forKey: .code) ?? projectId ?? ""
        self.projectId = projectId
        self.name = try c.decode(String.self, forKey: .name)
        self.code = code
        self.status = try c.decodeIfPresent(String.self, forKey: .status) ?? "active"
        self.address = try c.decodeIfPresent(String.self, forKey: .address)
            ?? c.decodeIfPresent(String.self, forKey: .description)
    }
}

struct ProjectDetailDto: Codable, Sendable {
    let id: String
    let code: String?
    let name: String
}

struct ProjectListResponseDto: Decodable, Sendable {
    let data: [ProjectListItemDto]
    let pagination: PaginationDto

    enum CodingKeys: String, CodingKey {
        case data
        case pagination
        case meta
    }

    init(data: [ProjectListItemDto], pagination: PaginationDto) {
        self.data = data
        self.pagination = pagination
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        data = try c.decode([ProjectListItemDto].self, forKey: .data)
        pagination = try c.decodeIfPresent(PaginationDto.self, forKey: .pagination)
            ?? c.decodeIfPresent(PaginationDto.self, forKey: .meta)
            ?? PaginationDto(page: 1, limit: data.count, total: data.count)
    }
}

struct ModulePermissionDto: Decodable, Sendable {
    let canCreate: Bool
    let canRead: Bool
    let canUpdate: Bool
    let canDelete: Bool
    let canAssign: Bool?
    let canCapture: Bool?
}

struct ProjectPermissionsDto: Decodable, Sendable {
    let modules: [String: ModulePermissionDto]
}
