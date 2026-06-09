import Foundation

nonisolated struct AppVersionInfoDto: Decodable, Sendable {
    let minimumVersion: String
    let latestVersion: String
    let forceUpdate: Bool?
    let appStoreURL: String
    let message: String?
    let releaseNotes: String?
}

enum AppVersionAPI: Sendable {
    static func fetchVersionInfo() async throws -> AppVersionInfoDto {
        let envelope: APIDataEnvelope<AppVersionInfoDto> = try await APIClient.shared.send(
            .GET,
            path: "app/version",
            queryItems: [URLQueryItem(name: "appId", value: "noblehall-cms")]
        )
        return envelope.data
    }
}
