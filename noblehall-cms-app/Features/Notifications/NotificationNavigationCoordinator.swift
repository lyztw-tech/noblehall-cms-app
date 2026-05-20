import Foundation
import Observation

/// 由通知深連結開啟任務詳情（全螢幕）。
@MainActor
@Observable
final class NotificationNavigationCoordinator {
    struct TaskDetailPresentation: Identifiable, Equatable {
        let id: String
        let projectCode: String
        let taskId: String
        let qualityDrawingId: String?
    }

    struct MyTasksFocus: Identifiable, Equatable {
        let id = UUID()
        let projectCode: String
        let taskId: String
        let qualityDrawingId: String?
    }

    var taskDetail: TaskDetailPresentation?
    var myTasksFocus: MyTasksFocus?
    var notificationInboxFocus: UUID?

    func open(deepLink: NotificationDeepLink, currentProjectCode: String) {
        if deepLink.projectCode != currentProjectCode {
            // 跨專案通知：仍嘗試在目前專案開啟任務（多數連結為當前專案）。
        }
        guard let route = deepLink.taskDetailRoute else { return }
        myTasksFocus = MyTasksFocus(
            projectCode: route.projectCode,
            taskId: route.taskId,
            qualityDrawingId: route.qualityDrawingId
        )
    }

    func open(link: String, currentProjectCode: String) {
        guard let deepLink = NotificationDeepLink.parse(link: link) else {
            openInbox()
            return
        }
        open(deepLink: deepLink, currentProjectCode: currentProjectCode)
    }

    func openInbox() {
        notificationInboxFocus = UUID()
    }

    func clear() {
        taskDetail = nil
    }

    func clearMyTasksFocus(id: MyTasksFocus.ID) {
        guard myTasksFocus?.id == id else { return }
        myTasksFocus = nil
    }
}
