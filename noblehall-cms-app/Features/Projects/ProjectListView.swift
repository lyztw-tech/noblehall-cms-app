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
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    NobleHallSectionHeader(
                        eyebrow: "Projects",
                        title: "選擇工務專案",
                        subtitle: "請選擇今天要管理的建案。App 會自動同步任務與平面圖，讓現場作業更清楚。",
                        systemImage: "square.grid.2x2.fill"
                    )
                    .padding(.top, 12)

                    if !network.isConnected {
                        Label("離線模式：顯示上次同步的專案", systemImage: "wifi.slash")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(NobleHallTheme.warning)
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(NobleHallTheme.warning.opacity(0.1), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }

                    if let loadError {
                        Label(loadError, systemImage: "exclamationmark.triangle")
                            .font(.footnote)
                            .foregroundStyle(.red)
                            .padding(14)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }

                    VStack(spacing: 12) {
                        ForEach(projects) { project in
                            Button {
                                session.setSelectedProject(code: project.code)
                            } label: {
                                ProjectCard(project: project)
                            }
                            .buttonStyle(NobleHallPlainCardButtonStyle())
                        }
                    }

                    if isLoading, projects.isEmpty {
                        ProgressView("載入專案…")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 36)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 28)
            }
            .nobleHallScreen()
            .navigationTitle("專案")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("登出") { Task { await logout() } }
                        .foregroundStyle(NobleHallTheme.brandGold)
                }
            }
            .refreshable { await load(force: true) }
            .task { await load(force: false) }
        }
    }

    private struct ProjectCard: View {
        let project: ProjectListItemDto

        var body: some View {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(NobleHallTheme.brandGold.opacity(0.12))
                    Image(systemName: "building.2.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundStyle(NobleHallTheme.brandGold)
                }
                .frame(width: 52, height: 52)

                VStack(alignment: .leading, spacing: 5) {
                    Text(project.name)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(NobleHallTheme.ink)
                    HStack(spacing: 6) {
                        NobleHallStatusPill(title: project.code, systemImage: "number", tint: NobleHallTheme.brandGold)
                        if !project.status.isEmpty {
                            NobleHallStatusPill(title: project.status, systemImage: "checkmark.seal", tint: NobleHallTheme.success)
                        }
                    }
                    if let address = project.address, !address.isEmpty {
                        Text(address)
                            .font(.caption)
                            .foregroundStyle(NobleHallTheme.secondaryInk)
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(NobleHallTheme.softGold)
            }
            .padding(16)
            .nobleHallCard(cornerRadius: 20)
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
