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
            Group {
                if isLoading, projects.isEmpty {
                    ProgressView("載入專案…")
                } else {
                    List {
                        if !network.isConnected {
                            Section {
                                HStack {
                                    NobleHallOfflineTag(text: "快取專案")
                                    Spacer(minLength: 0)
                                }
                                .nobleHallOfflineListTagRow()
                            }
                        }
                        if let loadError {
                            Section {
                                Label(loadError, systemImage: "exclamationmark.triangle")
                                    .font(.footnote)
                                    .foregroundStyle(.red)
                            }
                        }
                        Section {
                            ForEach(projects) { project in
                                Button {
                                    session.setSelectedProject(code: project.code)
                                } label: {
                                    ProjectRow(project: project)
                                }
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                    .background(NobleHallTheme.warmBackground)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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

    private struct ProjectRow: View {
        let project: ProjectListItemDto

        var body: some View {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(NobleHallTheme.brandGold.opacity(0.12))
                    Image(systemName: "building.2.fill")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(NobleHallTheme.brandGold)
                }
                .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 5) {
                    Text(project.name)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(NobleHallTheme.ink)
                    if !project.status.isEmpty {
                        NobleHallStatusPill(title: project.status, systemImage: "checkmark.seal", tint: NobleHallTheme.success)
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
                    .font(.caption.weight(.bold))
                    .foregroundStyle(NobleHallTheme.softGold)
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
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
            loadError = error.userFacingMessage
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
