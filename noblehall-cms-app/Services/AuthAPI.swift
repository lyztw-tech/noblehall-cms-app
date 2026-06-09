import Foundation

enum AuthAPI: Sendable {
    static func login(account: String, password: String) async throws -> LoginResponseDto {
        let envelope: APIDataEnvelope<LoginResponseDto> = try await APIClient.shared.send(
            .POST,
            path: "auth/login",
            body: LoginRequestBody(account: account, password: password)
        )
        return envelope.data
    }

    static func fetchMe() async throws -> UserDto {
        let envelope: APIDataEnvelope<UserDto> = try await APIClient.shared.send(.GET, path: "auth/me")
        return envelope.data
    }

    static func refreshSession() async throws {
        guard let refreshToken = AuthTokenStore.refreshToken, !refreshToken.isEmpty else {
            throw APIRequestError.httpStatus(code: 401, body: nil)
        }
        let envelope: APIDataEnvelope<RefreshTokenResponseDto> = try await APIClient.shared.send(
            .POST,
            path: "auth/refresh",
            body: RefreshTokenRequestBody(refreshToken: refreshToken)
        )
        AuthTokenStore.save(accessToken: envelope.data.accessToken, refreshToken: envelope.data.refreshToken)
    }

    static func logout() async throws {
        try await APIClient.shared.sendVoid(.POST, path: "auth/logout")
    }
}
