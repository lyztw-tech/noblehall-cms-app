import SwiftData
import SwiftUI

struct MainTabView: View {
    let projectCode: String
    @Environment(SessionStore.self) private var session
    @Environment(NetworkPathMonitor.self) private var network
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        TabView {
            MyTasksView(projectCode: projectCode)
                .tabItem { Label("我的任務", systemImage: "checklist.checked") }
            NavigationStack {
                TaskManagementRootView(projectCode: projectCode)
            }
            .tabItem { Label("任務管理", systemImage: "map.fill") }
            SettingsView(projectCode: projectCode)
                .tabItem { Label("設定", systemImage: "gearshape.fill") }
        }
        .tint(NobleHallTheme.brandGold)
        .toolbarBackground(.hidden, for: .tabBar)
    }
}
