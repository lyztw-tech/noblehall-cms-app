import Foundation

enum ProjectAPI: Sendable {
    static func projectDetail(projectCode: String, spaceId: String) async throws -> ProjectDetailDto {
        try await APIClient.shared.send(
            .GET,
            path: "projects/\(projectCode)",
            spaceId: spaceId
        )
    }

    static func listProjects(spaceId: String, page: Int = 1, limit: Int = 100) async throws -> ProjectListResponseDto {
        try await APIClient.shared.send(
            .GET,
            path: "projects",
            queryItems: [
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "limit", value: String(limit)),
            ],
            spaceId: spaceId
        )
    }
}
