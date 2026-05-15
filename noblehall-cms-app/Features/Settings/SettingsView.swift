import SwiftData
import SwiftUI

struct SettingsView: View {
    let projectCode: String
    @Environment(SessionStore.self) private var session
    @Environment(NetworkPathMonitor.self) private var network
    @Environment(\.modelContext) private var modelContext
    @Bindable private var planPreload = PlanAssetPreloadStore.shared

    @State private var cacheStats: PlanAssetCacheStats?
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
                    LabeledContent("目前專案", value: projectCode)
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
            planCacheSection
                Section {
                    Button("登出", role: .destructive) {
                        Task { await logout() }
                    }
                }
            }
            .navigationTitle("設定")
            .task(id: projectCode) { await refreshCacheStats() }
            .onChange(of: planPreload.lastCompletedAt) { _, _ in
                Task { await refreshCacheStats() }
            }
            .onChange(of: network.isConnected) { _, online in
                if online, let sid = session.spaceId {
                    Task {
                        await OutboxSync.flushPending(modelContext: modelContext, spaceId: sid, isOnline: true)
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
    private var planCacheSection: some View {
        Section {
            if planPreload.isRunning {
                HStack(spacing: 12) {
                    ProgressView()
                    VStack(alignment: .leading, spacing: 2) {
                        Text("正在下載平面圖與座標點…")
                        if let progress = planPreload.progressText {
                            Text(progress)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if let stats = cacheStats {
                LabeledContent("平面圖", value: "\(stats.drawingCount) 張")
                LabeledContent("圖檔已下載", value: "\(stats.drawingsWithImageCount) / \(stats.drawingCount) 張")
                LabeledContent("座標點", value: "\(stats.totalPointCount) 個")
                LabeledContent("暫存空間", value: PlanAssetCache.formattedByteCount(stats.totalBytes))
                if stats.imageBytes > 0 {
                    LabeledContent("　├ 圖檔", value: PlanAssetCache.formattedByteCount(stats.imageBytes))
                }
                if stats.metadataBytes > 0 {
                    LabeledContent("　└ 座標資料", value: PlanAssetCache.formattedByteCount(stats.metadataBytes))
                }
            } else {
                Text("尚無離線暫存")
                    .foregroundStyle(.secondary)
            }
            if let completed = planPreload.lastCompletedAt {
                LabeledContent("上次更新", value: Self.formatLastUpdated(completed))
            }
            if planPreload.lastImagesCachedCount > 0, let stats = cacheStats {
                LabeledContent("上次預載圖檔", value: "\(planPreload.lastImagesCachedCount) / \(stats.drawingCount) 張")
            }
            if let pending = try? TaskCreateOutbox.pendingCount(context: modelContext), pending > 0 {
                LabeledContent("待上傳任務", value: "\(pending) 筆")
            }
            if let pendingExec = try? ExecutionOutbox.pendingCount(context: modelContext), pendingExec > 0 {
                LabeledContent("待上傳執行紀錄", value: "\(pendingExec) 筆")
            }
            if let err = planPreload.lastError, !err.isEmpty {
                Text(err)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
            Button("清除此專案離線暫存…", role: .destructive) {
                showClearProjectCacheConfirm = true
            }
            .disabled(planPreload.isRunning)
            .confirmationDialog(
                "將刪除此專案的任務列表快取、任務詳情、平面圖與新增任務表單資料；不影響帳號與待上傳佇列。",
                isPresented: $showClearProjectCacheConfirm,
                titleVisibility: .visible
            ) {
                Button("清除", role: .destructive) {
                    Task { await clearProjectOfflineCaches() }
                }
                Button("取消", role: .cancel) {}
            }
            Button("重新下載暫存") {
                Task { await redownloadPlanCache() }
            }
            .disabled(planPreload.isRunning || !network.isConnected)
        } header: {
            Text("離線平面圖暫存")
        } footer: {
            Text("連線後會自動下載平面圖、座標點與新增任務表單資料；離線可暫存新任務與執行紀錄（含照片），連線後自動上傳。登出時會先嘗試上傳佇列（須連線），接著清除本機暫存與佇列，避免他人使用裝置時看到前一帳號資料；若離線登出，尚未上傳的暫存將一併移除。")
        }
    }

    private static let lastUpdatedFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_TW")
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private static func formatLastUpdated(_ date: Date) -> String {
        lastUpdatedFormatter.string(from: date)
    }

    private func refreshCacheStats() async {
        await PlanAssetCache.repairCachedPNGs(projectCode: projectCode, context: modelContext)
        try? modelContext.save()
        cacheStats = try? PlanAssetCache.stats(projectCode: projectCode, context: modelContext)
    }

    private func redownloadPlanCache() async {
        guard let sid = session.spaceId, network.isConnected else { return }
        await PlanAssetCache.preloadAll(
            projectCode: projectCode,
            spaceId: sid,
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
            cacheMaintenanceError = error.localizedDescription
        }
    }

    private func logout() async {
        if network.isConnected, let sid = session.spaceId {
            await OutboxSync.flushPending(modelContext: modelContext, spaceId: sid, isOnline: true)
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
