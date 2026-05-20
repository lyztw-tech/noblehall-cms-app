import Foundation
import UserNotifications

/// 偵測「離線 → 恢復連線」並發送**本地通知**（非推播）；需使用者曾同意通知權限。
@MainActor
enum NetworkReconnectNotifier {
    /// 曾短暫斷線至少此秒數後恢復連線，才發通知（過濾抖動）。
    private static let minimumDisconnectedSeconds: TimeInterval = 1.5

    private static var lastDisconnectAt: Date?
    private static var didRequestAuthorization = false

    /// App 啟動後可呼叫一次：僅在「尚未決定」時向系統請求通知權限。
    static func requestAuthorizationIfNotDetermined() async {
        guard !didRequestAuthorization else { return }
        didRequestAuthorization = true
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    /// 由 `AppRootView` 在 `network.isConnected` 變化時呼叫。
    static func handleTransition(wasConnected: Bool, isConnected: Bool, isLoggedIn: Bool) async {
        if wasConnected, !isConnected {
            lastDisconnectAt = Date()
            return
        }
        guard !wasConnected, isConnected else { return }
        guard let disconnectedAt = lastDisconnectAt else { return }
        lastDisconnectAt = nil
        guard Date().timeIntervalSince(disconnectedAt) >= minimumDisconnectedSeconds else { return }

        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            break
        default:
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "已恢復網路連線"
        if isLoggedIn {
            content.body = "連線已恢復，待上傳的任務與執行紀錄將在背景下同步。"
        } else {
            content.body = "連線已恢復。"
        }
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "lyztw.noblehall.reconnect.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        try? await center.add(request)
    }
}
