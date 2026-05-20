import Foundation
import UIKit

enum NotificationAPI: Sendable {
    private struct APNsDeviceTokenBody: Encodable {
        let token: String
        let environment: String
        let bundleId: String
        let appVersion: String
        let deviceName: String
    }

    private static var apnsEnvironment: String {
        AppConfiguration.environmentName.trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare("Production") == .orderedSame ? "production" : "sandbox"
    }

    static func list(
        page: Int = 1,
        limit: Int = 20,
        unreadOnly: Bool = false,
        spaceId: String?
    ) async throws -> NotificationListDto {
        var items = [
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "limit", value: String(limit)),
        ]
        if unreadOnly {
            items.append(URLQueryItem(name: "unreadOnly", value: "true"))
        }
        return try await APIClient.shared.send(
            .GET,
            path: "notifications",
            queryItems: items,
            spaceId: spaceId
        )
    }

    static func unreadCount(spaceId: String?) async throws -> Int {
        let dto: UnreadCountDto = try await APIClient.shared.send(
            .GET,
            path: "notifications/unread-count",
            spaceId: spaceId
        )
        return dto.count
    }

    static func markRead(id: String, spaceId: String?) async throws {
        try await APIClient.shared.sendVoid(
            .PATCH,
            path: "notifications/\(id)/read",
            spaceId: spaceId
        )
    }

    static func markAllRead(spaceId: String?) async throws -> Int {
        let dto: MarkAllReadResponseDto = try await APIClient.shared.send(
            .PATCH,
            path: "notifications/read-all",
            spaceId: spaceId
        )
        return dto.count
    }

    static func clearAll(spaceId: String?) async throws -> Int {
        let dto: MarkAllReadResponseDto = try await APIClient.shared.send(
            .DELETE,
            path: "notifications",
            spaceId: spaceId
        )
        return dto.count
    }

    static func registerAPNsDeviceToken(_ token: String, spaceId: String?) async throws {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let deviceName = await MainActor.run { UIDevice.current.name }
        try await APIClient.shared.sendVoid(
            .POST,
            path: "notifications/apns-device-token",
            body: APNsDeviceTokenBody(
                token: trimmed,
                environment: apnsEnvironment,
                bundleId: AppMetadata.bundleIdentifier,
                appVersion: AppMetadata.version,
                deviceName: deviceName
            ),
            spaceId: spaceId
        )
    }
}
