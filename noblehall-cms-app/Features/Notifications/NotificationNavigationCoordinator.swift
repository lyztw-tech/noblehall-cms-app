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

    var taskDetail: TaskDetailPresentation?

    func open(deepLink: NotificationDeepLink, currentProjectCode: String) {
        if deepLink.projectCode != currentProjectCode {
            // 跨專案通知：仍嘗試在目前專案開啟任務（多數連結為當前專案）。
        }
        guard let route = deepLink.taskDetailRoute else { return }
        taskDetail = TaskDetailPresentation(
            id: route.taskId,
            projectCode: route.projectCode,
            taskId: route.taskId,
            qualityDrawingId: route.qualityDrawingId
        )
    }

    func open(link: String, currentProjectCode: String) {
        guard let deepLink = NotificationDeepLink.parse(link: link) else { return }
        open(deepLink: deepLink, currentProjectCode: currentProjectCode)
    }

    func clear() {
        taskDetail = nil
    }
}
