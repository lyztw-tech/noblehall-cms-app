import Foundation

struct UserDto: Codable, Sendable, Identifiable {
    let id: String
    let username: String
    let displayName: String
    let email: String?
    let phone: String?
    let permissions: [String]?
    let role: String?
    let spaceId: String?
    let isSystemAdmin: Bool?
    let mustChangePassword: Bool?
    /// `GET /auth/me` 未帶 `x-space-id` 時回傳，供選定 Space。
    let spaceIds: [String]?
}

struct LoginRequestBody: Encodable, Sendable {
    let username: String
    let password: String
}
