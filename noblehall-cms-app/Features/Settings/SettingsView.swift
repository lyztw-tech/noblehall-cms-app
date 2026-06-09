import SwiftData
import SwiftUI

struct SettingsView: View {
    let projectCode: String
    @Environment(SessionStore.self) private var session
    @Environment(NetworkPathMonitor.self) private var network
    @Environment(\.modelContext) private var modelContext
    @Bindable private var planPreload = PlanAssetPreloadStore.shared

    @State private var offlineUsedBytes: Int64 = 0
    @State private var availableBytes: Int64?
    @State private var showClearProjectCacheConfirm = false
    @State private var cacheMaintenanceError: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("個人資料") {
                    if let u = session.currentUser {
                        LabeledContent("顯示名稱", value: u.displayName)
                        LabeledContent("帳號", value: u.username)
                        if let email = u.email, !email.isEmpty {
                            LabeledContent("Email", value: email)
                        }
                    }
                }
                Section("專案") {
                    LabeledContent("目前專案", value: session.selectedProjectName ?? projectCode)
                    Button("切換專案") {
                        session.setSelectedProject(code: nil)
                    }
                }
                if let cacheMaintenanceError, !cacheMaintenanceError.isEmpty {
                Section {
                    Text(cacheMaintenanceError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
            offlineDataSection
                Section {
                    Button("登出", role: .destructive) {
                        Task { await logout() }
                    }
                }
            }
            .listSectionSpacing(14)
            .listRowBackground(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(AppTheme.cardBackground)
            )
            .appScreen()
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            .task(id: projectCode) { await refreshCacheStats() }
            .onChange(of: planPreload.lastCompletedAt) { _, _ in
                Task { await refreshCacheStats() }
            }
            .onChange(of: network.isConnected) { _, online in
                if online {
                    Task {
                        await OutboxSync.flushPending(modelContext: modelContext, isOnline: true)
                        await refreshCacheStats()
                    }
                }
            }
            .onChange(of: planPreload.isRunning) { _, running in
                if !running { Task { await refreshCacheStats() } }
            }
        }
    }

    @ViewBuilder
    private var offlineDataSection: some View {
        Section {
            if planPreload.isRunning {
                HStack(spacing: 12) {
                    ProgressView()
                    VStack(alignment: .leading, spacing: 2) {
                        Text("正在刷新離線資料…")
                        if let progress = planPreload.progressText {
                            Text(progress)
                                .font(.caption)
                                .foregroundStyle(AppTheme.secondaryInk)
                        }
                    }
                }
            }

            LabeledContent("已使用空間", value: PlanAssetCache.formattedByteCount(offlineUsedBytes))
            LabeledContent(
                "可用空間",
                value: availableBytes.map { PlanAssetCache.formattedByteCount($0) } ?? "—"
            )
            LabeledContent("上次更新", value: lastUpdatedLabel)

            if let err = planPreload.lastError, !err.isEmpty {
                Text(err)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            Button("刷新資料") {
                Task { await redownloadPlanCache() }
            }
            .disabled(planPreload.isRunning || !network.isConnected)

            Button("清除暫存資料", role: .destructive) {
                showClearProjectCacheConfirm = true
            }
            .disabled(planPreload.isRunning)
            .confirmationDialog(
                "清除暫存資料",
                isPresented: $showClearProjectCacheConfirm,
                titleVisibility: .visible
            ) {
                Button("清除", role: .destructive) {
                    Task { await clearProjectOfflineCaches() }
                }
                Button("取消", role: .cancel) {}
            } message: {
                Text("將刪除此專案的本機任務、平面圖與表單快取；不影響帳號，待上傳佇列仍會保留。")
            }
        } header: {
            Text("離線資料")
        } footer: {
            Text(
                "本機會保留此專案的任務列表與詳情、品質平面圖與座標點、新增任務表單，以及離線暫存尚未上傳的任務與執行紀錄（含照片）。連線後可按「刷新資料」同步最新內容。"
            )
        }
    }

    private var lastUpdatedLabel: String {
        guard let completed = planPreload.lastCompletedAt else { return "尚未刷新" }
        return AppDateTimeFormat.fullDateTime(completed)
    }

    private func refreshCacheStats() async {
        await PlanAssetCache.repairCachedPNGs(projectCode: projectCode, context: modelContext)
        try? modelContext.save()
        offlineUsedBytes = (try? CacheMaintenance.projectOfflineUsedBytes(
            projectCode: projectCode,
            context: modelContext
        )) ?? 0
        availableBytes = CacheMaintenance.deviceAvailableStorageBytes()
    }

    private func redownloadPlanCache() async {
        guard network.isConnected else { return }
        await PlanAssetCache.preloadAll(
            projectCode: projectCode,
            context: modelContext,
            force: true
        )
        await refreshCacheStats()
    }

    private func clearProjectOfflineCaches() async {
        cacheMaintenanceError = nil
        do {
            try CacheMaintenance.purgeOfflineDataForProject(projectCode: projectCode, modelContext: modelContext)
            await refreshCacheStats()
        } catch {
            cacheMaintenanceError = error.userFacingMessage
        }
    }

    private func logout() async {
        if network.isConnected {
            await OutboxSync.flushPending(modelContext: modelContext, isOnline: true)
        }
        do { try await AuthAPI.logout() } catch {}
        do {
            try CacheMaintenance.purgeAllLocalDataAfterLogout(modelContext: modelContext)
        } catch {
            // 仍應登出；快取清除失敗僅影響本機殘留
        }
        session.clearSession()
    }
}
