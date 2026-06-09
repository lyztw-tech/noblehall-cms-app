import Foundation

nonisolated struct UserDto: Codable, Sendable, Identifiable {
    let id: String
    let account: String
    let email: String?
    let name: String
    let hasAvatar: Bool?
    let systemRole: String
    let tenantId: String?

    var username: String { account }
    var displayName: String { name }
    var phone: String? { nil }
    var permissions: [String]? { nil }
    var role: String? { systemRole }
    var isSystemAdmin: Bool? { systemRole == "platform_admin" }
    var mustChangePassword: Bool? { false }
}

nonisolated struct LoginRequestBody: Encodable, Sendable {
    let account: String
    let password: String
}

nonisolated struct LoginResponseDto: Codable, Sendable {
    let accessToken: String
    let refreshToken: String
    let user: UserDto
}

nonisolated struct RefreshTokenRequestBody: Encodable, Sendable {
    let refreshToken: String
}

nonisolated struct RefreshTokenResponseDto: Codable, Sendable {
    let accessToken: String
    let refreshToken: String
}

nonisolated struct APIDataEnvelope<T: Decodable>: Decodable {
    let data: T
}
