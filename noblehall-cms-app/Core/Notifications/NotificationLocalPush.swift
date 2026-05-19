import Foundation
import UserNotifications

/// App 內 SSE／輪詢發現新通知時，於 iOS 通知中心顯示（與 Web Push 並行）。
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
            return true
        case .denied:
            return false
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) == true
        @unknown default:
            return false
        }
    }

    static func postNewNotification(title: String, body: String?, link: String?) async {
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
}
