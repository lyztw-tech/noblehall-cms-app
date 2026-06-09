import Foundation

enum ProjectAPI: Sendable {
    static func projectDetail(projectCode: String) async throws -> ProjectDetailDto {
        let envelope: APIDataEnvelope<ProjectDetailDto> = try await APIClient.shared.send(
            .GET,
            path: "projects/\(projectCode)"
        )
        return envelope.data
    }

    static func listProjects(page: Int = 1, limit: Int = 100) async throws -> ProjectListResponseDto {
        try await APIClient.shared.send(
            .GET,
            path: "projects",
            queryItems: [
                URLQueryItem(name: "page", value: String(page)),
                URLQueryItem(name: "limit", value: String(limit)),
            ]
        )
    }

    static func myPermissions(projectCode: String) async throws -> ProjectPermissionsDto {
        let envelope: APIDataEnvelope<ProjectPermissionsDto> = try await APIClient.shared.send(
            .GET,
            path: "projects/\(projectCode)/my-permissions"
        )
        return envelope.data
    }
}
