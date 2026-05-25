import Foundation
import UIKit

enum NotificationAPI: Sendable {
    private struct APNsDeviceTokenBody: Encodable {
        let token: String
        let environment: String
        let bundleId: String
        let deviceId: String?
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
        let dto: APIDataEnvelope<UnreadCountDto> = try await APIClient.shared.send(
            .GET,
            path: "notifications/unread-count",
            spaceId: spaceId
        )
        return dto.data.count
    }

    static func markRead(id: String, spaceId: String?) async throws {
        try await APIClient.shared.sendVoid(
            .PATCH,
            path: "notifications/\(id)/read",
            spaceId: spaceId
        )
    }

    static func markAllRead(spaceId: String?) async throws -> Int {
        let dto: APIDataEnvelope<MarkAllReadResponseDto> = try await APIClient.shared.send(
            .PATCH,
            path: "notifications/read-all",
            body: EmptyRequestBody(),
            spaceId: spaceId
        )
        return dto.data.count
    }

    static func clearAll(spaceId: String?) async throws -> Int {
        let dto: APIDataEnvelope<MarkAllReadResponseDto> = try await APIClient.shared.send(
            .PATCH,
            path: "notifications/dismiss-all",
            body: EmptyRequestBody(),
            spaceId: spaceId
        )
        return dto.data.count
    }

    static func registerAPNsDeviceToken(_ token: String, spaceId: String?) async throws {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let deviceName = await MainActor.run { UIDevice.current.name }
        let deviceId = await MainActor.run { UIDevice.current.identifierForVendor?.uuidString }
        try await APIClient.shared.sendVoid(
            .POST,
            path: "notifications/device-tokens/ios",
            body: APNsDeviceTokenBody(
                token: trimmed,
                environment: apnsEnvironment,
                bundleId: AppMetadata.bundleIdentifier,
                deviceId: deviceId,
                appVersion: AppMetadata.version,
                deviceName: deviceName
            ),
            spaceId: spaceId
        )
    }
}
