import Foundation

/// 解析後端通知 `link`（Construction mobile: `constructionapp://projects/{projectId}/quality/tasks/{taskId}`）。
struct NotificationDeepLink: Sendable, Equatable {
    let projectCode: String
    let qualityDrawingId: String?
    let openTaskId: String?

    /// 由通知列表或推播點擊導向任務詳情。
    var taskDetailRoute: (projectCode: String, taskId: String, qualityDrawingId: String?)? {
        guard let openTaskId, !openTaskId.isEmpty else { return nil }
        return (projectCode, openTaskId, qualityDrawingId)
    }

    static func parse(link: String?) -> NotificationDeepLink? {
        guard let link, !link.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }

        let pathAndQuery: String
        if link.hasPrefix("constructionapp://"), let url = URL(string: link) {
            let host = url.host.map { "/\($0)" } ?? ""
            pathAndQuery = host + url.path + (url.query.map { "?\($0)" } ?? "")
        } else if link.hasPrefix("http://") || link.hasPrefix("https://") {
            guard let url = URL(string: link) else { return nil }
            pathAndQuery = url.path + (url.query.map { "?\($0)" } ?? "")
        } else {
            pathAndQuery = link.hasPrefix("/") ? link : "/\(link)"
        }

        let question = pathAndQuery.firstIndex(of: "?")
        let path = question.map { String(pathAndQuery[..<$0]) } ?? pathAndQuery
        let query = question.map { String(pathAndQuery[pathAndQuery.index(after: $0)...]) } ?? ""

        // /projects/:projectCode/quality/task-management/:taskId
        let segments = path.split(separator: "/").map(String.init)
        // constructionapp://projects/:projectId/quality/tasks/:taskId
        // /p/:projectId/quality/tasks/:taskId
        if segments.count >= 5,
           (segments[0] == "projects" || segments[0] == "p"),
           segments[2] == "quality",
           segments[3] == "tasks" {
            let projectCode = segments[1]
            let taskId = segments[4].removingPercentEncoding ?? segments[4]
            guard !taskId.isEmpty else { return nil }
            return NotificationDeepLink(projectCode: projectCode, qualityDrawingId: nil, openTaskId: taskId)
        }

        if segments.count >= 5,
           segments[0] == "projects",
           segments[2] == "quality",
           segments[3] == "task-management" {
            let projectCode = segments[1]
            let taskId = segments[4].removingPercentEncoding ?? segments[4]
            guard !taskId.isEmpty else { return nil }
            return NotificationDeepLink(
                projectCode: projectCode,
                qualityDrawingId: nil,
                openTaskId: taskId
            )
        }

        // /projects/:projectCode/quality/drawings/:qualityDrawingId?openTaskId=:taskId
        guard segments.count >= 5,
              segments[0] == "projects",
              segments[2] == "quality",
              segments[3] == "drawings"
        else { return nil }

        let projectCode = segments[1]
        let drawingId = segments[4]
        var openTaskId: String?
        if !query.isEmpty {
            let params = query.split(separator: "&").map(String.init)
            for pair in params {
                let kv = pair.split(separator: "=", maxSplits: 1).map(String.init)
                if kv.count == 2, kv[0] == "openTaskId" {
                    openTaskId = kv[1].removingPercentEncoding ?? kv[1]
                }
            }
        }

        return NotificationDeepLink(
            projectCode: projectCode,
            qualityDrawingId: drawingId.isEmpty ? nil : drawingId,
            openTaskId: openTaskId
        )
    }
}

extension Notification.Name {
    /// `userInfo["link"]` 為通知深連結字串。
    static let appNotificationDeepLink = Notification.Name("app.notification.deepLink")
    static let appRemoteNotificationReceived = Notification.Name("app.remoteNotification.received")
    static let appRemoteNotificationTokenUpdated = Notification.Name("app.remoteNotification.tokenUpdated")
    static let appRemoteNotificationTokenFailed = Notification.Name("app.remoteNotification.tokenFailed")
}
