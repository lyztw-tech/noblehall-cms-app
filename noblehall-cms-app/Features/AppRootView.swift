import SwiftData
import SwiftUI
import UIKit

struct AppRootView: View {
    @Environment(SessionStore.self) private var session
    @Environment(NetworkPathMonitor.self) private var network
    @Environment(NotificationInboxStore.self) private var notificationInbox
    @Environment(NotificationNavigationCoordinator.self) private var notificationNav
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase
    @State private var appUpdateGate = AppUpdateGate()
    @State private var showLaunchSplash = true
    @State private var latestRemoteNotificationToken: String?

    var body: some View {
        Group {
            if !session.isLoggedIn {
                LoginView()
            } else if session.selectedProjectCode == nil {
                ProjectListView()
                    .task { await notificationInbox.syncFromServer() }
            } else if let code = session.selectedProjectCode {
                MainTabView(projectCode: code)
            }
        }
        .tint(AppTheme.brandGold)
        .fullScreenCover(item: taskDetailBinding) { presentation in
            TaskDetailView(
                projectCode: presentation.projectCode,
                taskId: presentation.taskId,
                qualityDrawingIdHint: presentation.qualityDrawingId,
                onClose: { notificationNav.clear() }
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: .appNotificationDeepLink)) { note in
            guard let link = note.userInfo?["link"] as? String else { return }
            if let deepLink = notificationInbox.handleDeepLinkString(link) {
                openNotificationDeepLink(deepLink)
            } else {
                notificationNav.openInbox()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .appRemoteNotificationReceived)) { _ in
            guard session.isLoggedIn else { return }
            Task { await notificationInbox.syncFromServer() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .appRemoteNotificationTokenUpdated)) { note in
            guard let token = note.userInfo?["token"] as? String, !token.isEmpty else { return }
            print("[APNs] token notification received tokenPrefix=\(token.prefix(12))")
            latestRemoteNotificationToken = token
            Task { await registerRemoteNotificationTokenIfPossible(token) }
        }
        .overlay {
            if showLaunchSplash {
                AppLaunchSplashView()
                    .transition(.opacity.combined(with: .scale(scale: 1.015)))
                    .zIndex(10)
            }
        }
        .overlay {
            if let update = appUpdateGate.requiredUpdate {
                RequiredAppUpdateView(update: update) {
                    appUpdateGate.openAppStore()
                }
                .transition(.opacity)
                .zIndex(20)
            }
        }
        .dismissKeyboardOnTapOutside()
        .animation(.easeInOut(duration: 0.2), value: session.isLoggedIn)
        .animation(.easeInOut(duration: 0.2), value: session.selectedProjectCode)
        .animation(.easeOut(duration: 0.35), value: showLaunchSplash)
        .task(id: bootstrapTaskKey) {
            await bootstrapSessionAndPreload()
            syncNotificationInboxLifecycle()
        }
        .task {
            await appUpdateGate.checkForRequiredUpdate()
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            showLaunchSplash = false
        }
        .onChange(of: session.isLoggedIn) { _, loggedIn in
            if !loggedIn {
                notificationInbox.stop()
            } else {
                notificationInbox.startIfLoggedIn()
                if let latestRemoteNotificationToken {
                    Task { await registerRemoteNotificationTokenIfPossible(latestRemoteNotificationToken) }
                }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task { await appUpdateGate.checkForRequiredUpdate() }
            if session.isLoggedIn {
                notificationInbox.startIfLoggedIn()
            }
        }
        .task {
            await NetworkReconnectNotifier.requestAuthorizationIfNotDetermined()
        }
        .onChange(of: network.isConnected) { wasConnected, isConnected in
            Task {
                await NetworkReconnectNotifier.handleTransition(
                    wasConnected: wasConnected,
                    isConnected: isConnected,
                    isLoggedIn: session.isLoggedIn
                )
            }
            if isConnected {
                Task { await bootstrapSessionAndPreload() }
                if session.isLoggedIn {
                    notificationInbox.startIfLoggedIn()
                }
            }
        }
    }

    private var bootstrapTaskKey: String {
        "\(session.isLoggedIn)|\(session.selectedProjectCode ?? "")|\(network.isConnected)"
    }

    private var taskDetailBinding: Binding<NotificationNavigationCoordinator.TaskDetailPresentation?> {
        Binding(
            get: { notificationNav.taskDetail },
            set: { notificationNav.taskDetail = $0 }
        )
    }

    private func syncNotificationInboxLifecycle() {
        notificationInbox.bind(session: session)
        if session.isLoggedIn {
            notificationInbox.startIfLoggedIn()
        } else {
            notificationInbox.stop()
            notificationNav.clear()
        }
    }

    private func openNotificationDeepLink(_ deepLink: NotificationDeepLink) {
        if session.selectedProjectCode != deepLink.projectCode {
            session.setSelectedProject(code: deepLink.projectCode)
        }
        notificationNav.open(deepLink: deepLink, currentProjectCode: deepLink.projectCode)
    }

    private func registerRemoteNotificationTokenIfPossible(_ token: String) async {
        guard session.isLoggedIn else { return }
        do {
            try await NotificationAPI.registerAPNsDeviceToken(token)
            print("[APNs] device token uploaded")
        } catch {
            print("[APNs] device token upload failed: \(error.localizedDescription)")
        }
    }

    /// 先還原登入（Cookie），再預載平面圖；避免預載搶跑導致圖檔下載失敗、僅有座標點。
    private func bootstrapSessionAndPreload() async {
        if session.currentUser == nil {
            await session.restoreSessionIfPossible()
            try? await Task.sleep(nanoseconds: 400_000_000)
        }
        guard session.isLoggedIn,
              let projectCode = session.selectedProjectCode,
              network.isConnected
        else { return }

        await OutboxSync.flushPending(modelContext: modelContext, isOnline: true)
        await PlanAssetCache.preloadAll(
            projectCode: projectCode,
            context: modelContext,
            force: false
        )
        if let stats = try? PlanAssetCache.stats(projectCode: projectCode, context: modelContext),
           stats.drawingCount > 0,
           stats.drawingsWithImageCount < stats.drawingCount,
           network.isConnected {
            try? await Task.sleep(nanoseconds: 800_000_000)
            await PlanAssetCache.preloadAll(
                projectCode: projectCode,
                context: modelContext,
                force: true
            )
        }
    }
}
