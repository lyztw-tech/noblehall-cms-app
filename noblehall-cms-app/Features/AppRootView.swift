import SwiftData
import SwiftUI

struct AppRootView: View {
    @Environment(SessionStore.self) private var session
    @Environment(NetworkPathMonitor.self) private var network
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        Group {
            if !session.isLoggedIn {
                LoginView()
            } else if session.selectedProjectCode == nil {
                ProjectListView()
            } else if let code = session.selectedProjectCode {
                MainTabView(projectCode: code)
            }
        }
        .dismissKeyboardOnTapOutside()
        .animation(.easeInOut(duration: 0.2), value: session.isLoggedIn)
        .animation(.easeInOut(duration: 0.2), value: session.selectedProjectCode)
        .task(id: bootstrapTaskKey) {
            await bootstrapSessionAndPreload()
        }
        .onChange(of: network.isConnected) { _, online in
            guard online else { return }
            Task { await bootstrapSessionAndPreload() }
        }
    }

    private var bootstrapTaskKey: String {
        "\(session.isLoggedIn)|\(session.selectedProjectCode ?? "")|\(session.spaceId ?? "")|\(network.isConnected)"
    }

    /// 先還原登入（Cookie），再預載平面圖；避免預載搶跑導致圖檔下載失敗、僅有座標點。
    private func bootstrapSessionAndPreload() async {
        if session.currentUser == nil {
            await session.restoreSessionIfPossible()
            try? await Task.sleep(nanoseconds: 400_000_000)
        }
        guard session.isLoggedIn,
              let projectCode = session.selectedProjectCode,
              let spaceId = session.spaceId,
              network.isConnected
        else { return }

        await OutboxSync.flushPending(modelContext: modelContext, spaceId: spaceId, isOnline: true)
        await PlanAssetCache.preloadAll(
            projectCode: projectCode,
            spaceId: spaceId,
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
                spaceId: spaceId,
                context: modelContext,
                force: true
            )
        }
    }
}
