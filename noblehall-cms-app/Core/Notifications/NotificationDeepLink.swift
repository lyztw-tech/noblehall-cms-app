import Foundation

/// 解析後端通知 `link`（與 Web 相同：`/projects/{code}/quality/drawings/{id}?openTaskId=…`）。
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
        if link.hasPrefix("http://") || link.hasPrefix("https://") {
            guard let url = URL(string: link) else { return nil }
            pathAndQuery = url.path + (url.query.map { "?\($0)" } ?? "")
        } else {
            pathAndQuery = link.hasPrefix("/") ? link : "/\(link)"
        }

        let question = pathAndQuery.firstIndex(of: "?")
        let path = question.map { String(pathAndQuery[..<$0]) } ?? pathAndQuery
        let query = question.map { String(pathAndQuery[pathAndQuery.index(after: $0)...]) } ?? ""

        // /projects/:projectCode/quality/drawings/:qualityDrawingId
        let segments = path.split(separator: "/").map(String.init)
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
    static let nobleHallNotificationDeepLink = Notification.Name("nobleHall.notification.deepLink")
}
