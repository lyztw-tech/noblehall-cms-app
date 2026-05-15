import SwiftData
import SwiftUI

struct ProjectListView: View {
    @Environment(SessionStore.self) private var session
    @Environment(NetworkPathMonitor.self) private var network
    @Environment(\.modelContext) private var modelContext

    @State private var projects: [ProjectListItemDto] = []
    @State private var loadError: String?
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            List {
                if !network.isConnected {
                    Section {
                        Label("離線模式：顯示上次同步的專案", systemImage: "wifi.slash")
                            .font(.subheadline)
                    }
                }
                Section {
                    ForEach(projects) { p in
                        Button {
                            session.setSelectedProject(code: p.code)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(p.name).font(.headline)
                                Text(p.code).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("專案列表")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("登出") { Task { await logout() } }
                }
            }
            .overlay {
                if isLoading, projects.isEmpty { ProgressView() }
            }
            .refreshable { await load(force: true) }
            .task { await load(force: false) }
        }
    }

    private func load(force: Bool) async {
        guard let sid = session.spaceId else { return }
        if !network.isConnected {
            if let cached = try? LocalTaskCache.cachedProjects(context: modelContext), !cached.isEmpty {
                projects = cached.map {
                    ProjectListItemDto(projectId: nil, name: $0.name, code: $0.code, status: $0.status, address: nil)
                }
            }
            return
        }
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            let res = try await ProjectAPI.listProjects(spaceId: sid)
            projects = res.data
            try LocalTaskCache.upsertProjects(res.data, context: modelContext)
            try modelContext.save()
        } catch {
            loadError = error.localizedDescription
            if let cached = try? LocalTaskCache.cachedProjects(context: modelContext) {
                projects = cached.map {
                    ProjectListItemDto(projectId: nil, name: $0.name, code: $0.code, status: $0.status, address: nil)
                }
            }
        }
    }

    private func logout() async {
        do {
            try await AuthAPI.logout()
        } catch {
            // 仍清除本機狀態
        }
        session.clearSession()
    }
}
