import UIKit
import UserNotifications

/// 註冊通知中心 delegate：前景橫幅、點擊深連結導向任務等。
final class NoblehallAppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound, .badge])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        if let link = NotificationLocalPush.link(from: response.notification.request.content.userInfo) {
            NotificationCenter.default.post(
                name: .nobleHallNotificationDeepLink,
                object: nil,
                userInfo: ["link": link]
            )
        }
        completionHandler()
    }
}
