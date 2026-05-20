import Foundation
import UIKit
import UserNotifications

/// App 本機狀態通知，例如離線後恢復連線、離線資料同步完成或失敗。
/// 業務通知由後端透過 APNs 發送，避免同一筆通知在前景重複彈出。
enum NotificationLocalPush {
    private static let linkUserInfoKey = "nh.link"

    static func authorizationStatus() async -> UNAuthorizationStatus {
        await UNUserNotificationCenter.current().notificationSettings().authorizationStatus
    }

    /// 登入後請求權限（開發版／正式版皆可跳出系統詢問）。
    @discardableResult
    static func requestAuthorizationIfNeeded() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            if settings.badgeSetting != .enabled {
                _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
            }
            await registerForRemoteNotifications()
            return true
        case .denied:
            return false
        case .notDetermined:
            let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) == true
            if granted {
                await registerForRemoteNotifications()
            }
            return granted
        @unknown default:
            return false
        }
    }

    static func postNewNotification(title: String, body: String?, link: String?, badgeCount: Int? = nil) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized
            || settings.authorizationStatus == .provisional
            || settings.authorizationStatus == .ephemeral
        else {
            return
        }

        let content = UNMutableNotificationContent()
        content.title = title
        if let body, !body.isEmpty { content.body = body }
        if let link, !link.isEmpty {
            content.userInfo = [linkUserInfoKey: link]
        }
        content.sound = .default
        if let badgeCount {
            content.badge = NSNumber(value: badgeCount)
        }

        let request = UNNotificationRequest(
            identifier: "nh.inbox.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        try? await center.add(request)
    }

    static func link(from userInfo: [AnyHashable: Any]) -> String? {
        userInfo[linkUserInfoKey] as? String
    }

    private static func registerForRemoteNotifications() async {
        await MainActor.run {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }
}
