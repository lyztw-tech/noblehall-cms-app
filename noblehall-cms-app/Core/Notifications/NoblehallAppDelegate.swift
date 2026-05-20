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

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        print("[APNs] didRegister tokenPrefix=\(token.prefix(12)) length=\(token.count)")
        NotificationCenter.default.post(
            name: .nobleHallRemoteNotificationTokenUpdated,
            object: nil,
            userInfo: ["token": token]
        )
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        print("[APNs] didFailToRegister error=\(error.localizedDescription)")
        NotificationCenter.default.post(
            name: .nobleHallRemoteNotificationTokenFailed,
            object: nil,
            userInfo: ["error": error]
        )
    }

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        if let link = NotificationLocalPush.link(from: userInfo) {
            NotificationCenter.default.post(
                name: .nobleHallNotificationDeepLink,
                object: nil,
                userInfo: ["link": link]
            )
        }
        NotificationCenter.default.post(name: .nobleHallRemoteNotificationReceived, object: nil)
        completionHandler(.newData)
    }
}
