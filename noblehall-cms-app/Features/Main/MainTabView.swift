import Combine
import SwiftData
import SwiftUI

struct MainTabView: View {
    let projectCode: String
    @Environment(SessionStore.self) private var session
    @Environment(NetworkPathMonitor.self) private var network
    @Environment(NotificationInboxStore.self) private var inbox
    @Environment(NotificationNavigationCoordinator.self) private var notificationNav
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

    /// 前景時每 12 秒同步未讀（與 store 內輪詢互補，確保 Tab 角標即時更新）。
    private let foregroundSyncTimer = Timer.publish(every: 12, on: .main, in: .common).autoconnect()

    var body: some View {
        TabView {
            MyTasksView(projectCode: projectCode)
                .tabItem { Label("我的任務", systemImage: "checklist.checked") }

            NavigationStack {
                TaskManagementRootView(projectCode: projectCode)
            }
            .tabItem { Label("任務管理", systemImage: "map.fill") }

            NotificationInboxView(showsCloseButton: false, onOpenDeepLink: openNotificationDeepLink)
                .tabItem { Label("通知", systemImage: "tray.fill") }
                .modifier(UnreadTabBadgeModifier(count: inbox.unreadCount))

            SettingsView(projectCode: projectCode)
                .tabItem { Label("設定", systemImage: "gearshape.fill") }
        }
        .tint(NobleHallTheme.brandGold)
        .toolbarBackground(.hidden, for: .tabBar)
        .task {
            await inbox.syncFromServer()
        }
        .onAppear {
            Task { await inbox.syncFromServer() }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await inbox.syncFromServer() }
        }
        .onReceive(foregroundSyncTimer) { _ in
            guard scenePhase == .active else { return }
            Task { await inbox.syncFromServer() }
        }
    }

    private func openNotificationDeepLink(_ deepLink: NotificationDeepLink) {
        if deepLink.projectCode != projectCode {
            session.setSelectedProject(code: deepLink.projectCode)
        }
        notificationNav.open(deepLink: deepLink, currentProjectCode: deepLink.projectCode)
    }
}

/// 僅在未讀 > 0 時顯示 Tab 角標（`.badge(Int)` 不接受 nil）。
private struct UnreadTabBadgeModifier: ViewModifier {
    let count: Int

    func body(content: Content) -> some View {
        if count > 0 {
            content.badge(count)
        } else {
            content
        }
    }
}
