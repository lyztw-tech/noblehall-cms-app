import Foundation

enum AuthAPI: Sendable {
    static func login(username: String, password: String) async throws -> UserDto {
        try await APIClient.shared.send(
            .POST,
            path: "auth/login",
            body: LoginRequestBody(username: username, password: password),
            spaceId: nil
        )
    }

    static func fetchMe(spaceId: String?) async throws -> UserDto {
        try await APIClient.shared.send(.GET, path: "auth/me", spaceId: spaceId)
    }

    static func logout() async throws {
        try await APIClient.shared.sendVoid(.POST, path: "auth/logout", spaceId: nil)
    }
}
