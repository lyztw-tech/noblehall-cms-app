import Foundation
import Observation
import UserNotifications

/// 通知收件匣（與 Web `app-notification` store 對齊）：列表、未讀、輪詢、已讀。
@MainActor
@Observable
final class NotificationInboxStore {
    private(set) var items: [NotificationDto] = []
    private(set) var unreadCount: Int = 0
    private(set) var isLoading = false
    private(set) var isLoadingMore = false
    private(set) var loadError: String?
    /// 通知權限是否已開啟（供設定頁或除錯參考）。
    private(set) var isPushAuthorized = false

    private(set) var page = 1
    private(set) var limit = 20
    private(set) var totalPages = 0

    var hasMore: Bool { totalPages > 0 && page < totalPages }

    private var session: SessionStore?
    private var pollingTask: Task<Void, Never>?
    private var hasLoadedInboxOnce = false
    private var lastUnreadForPushCompare = 0
    private var hasEstablishedUnreadBaseline = false

    func bind(session: SessionStore) {
        self.session = session
    }

    func startIfLoggedIn() {
        guard let session, session.isLoggedIn, let spaceId = session.spaceId, !spaceId.isEmpty else {
            stop()
            return
        }
        Task {
            isPushAuthorized = await NotificationLocalPush.requestAuthorizationIfNeeded()
            await syncFromServer()
            startPolling()
        }
    }

    func stop() {
        pollingTask?.cancel()
        pollingTask = nil
        lastUnreadForPushCompare = 0
        hasEstablishedUnreadBaseline = false
        items = []
        unreadCount = 0
        page = 1
        totalPages = 0
        loadError = nil
        hasLoadedInboxOnce = false
    }

    /// 主畫面定期呼叫：拉未讀數（不依賴是否進入通知 Tab）。
    func syncFromServer() async {
        await refreshUnreadCount()
    }

    func refreshUnreadCount() async {
        guard let spaceId = session?.spaceId else { return }
        do {
            let newCount = try await NotificationAPI.unreadCount(spaceId: spaceId)
            unreadCount = newCount
            lastUnreadForPushCompare = newCount
            hasEstablishedUnreadBaseline = true
            await updateApplicationBadge()
        } catch {
            unreadCount = 0
            lastUnreadForPushCompare = 0
            await updateApplicationBadge()
        }
    }

    func fetchInbox(reset: Bool) async {
        guard let spaceId = session?.spaceId else { return }
        if reset {
            isLoading = true
            page = 1
        } else {
            isLoadingMore = true
        }
        loadError = nil
        defer {
            isLoading = false
            isLoadingMore = false
        }
        let targetPage = reset ? 1 : page + 1
        do {
            let res = try await NotificationAPI.list(page: targetPage, limit: limit, spaceId: spaceId)
            if reset {
                items = res.data
            } else {
                items.append(contentsOf: res.data)
            }
            page = res.pagination.page
            totalPages = res.pagination.totalPages
            hasLoadedInboxOnce = true
            await refreshUnreadCount()
        } catch {
            loadError = error.userFacingMessage
        }
    }

    func loadMoreIfNeeded() async {
        guard hasMore, !isLoading, !isLoadingMore else { return }
        await fetchInbox(reset: false)
    }

    func markRead(id: String) async {
        guard let spaceId = session?.spaceId else { return }
        if let idx = items.firstIndex(where: { $0.id == id }), items[idx].readAt == nil {
            items[idx] = items[idx].markedRead()
            unreadCount = max(0, unreadCount - 1)
            lastUnreadForPushCompare = unreadCount
            await updateApplicationBadge()
        }
        do {
            try await NotificationAPI.markRead(id: id, spaceId: spaceId)
            await refreshUnreadCount()
        } catch {
            await fetchInbox(reset: true)
        }
    }

    func markAllRead() async {
        guard let spaceId = session?.spaceId else { return }
        let now = Date()
        items = items.map { $0.readAt == nil ? $0.markedRead(at: now) : $0 }
        unreadCount = 0
        lastUnreadForPushCompare = 0
        await updateApplicationBadge()
        do {
            _ = try await NotificationAPI.markAllRead(spaceId: spaceId)
            await refreshUnreadCount()
        } catch {
            await fetchInbox(reset: true)
        }
    }

    func clearAll() async {
        guard let spaceId = session?.spaceId else { return }
        let snapshot = items
        let previousUnread = unreadCount
        items = []
        unreadCount = 0
        lastUnreadForPushCompare = 0
        hasEstablishedUnreadBaseline = true
        page = 1
        totalPages = 0
        loadError = nil
        await updateApplicationBadge()
        do {
            _ = try await NotificationAPI.clearAll(spaceId: spaceId)
            await refreshUnreadCount()
        } catch {
            items = snapshot
            unreadCount = previousUnread
            lastUnreadForPushCompare = previousUnread
            loadError = error.userFacingMessage
            await updateApplicationBadge()
        }
    }

    func handleTap(_ item: NotificationDto) -> NotificationDeepLink? {
        let deepLink = NotificationDeepLink.parse(link: item.link)
        if item.isUnread {
            Task { await markRead(id: item.id) }
        }
        return deepLink
    }

    func handleDeepLinkString(_ link: String) -> NotificationDeepLink? {
        NotificationDeepLink.parse(link: link)
    }

    private func startPolling() {
        pollingTask?.cancel()
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 12_000_000_000)
                guard let self, !Task.isCancelled else { return }
                await self.syncFromServer()
            }
        }
    }

    private func updateApplicationBadge() async {
        do {
            try await UNUserNotificationCenter.current().setBadgeCount(unreadCount)
        } catch {
            print("[APNs] setBadgeCount failed: \(error.localizedDescription)")
        }
    }
}
