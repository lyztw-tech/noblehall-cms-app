import SwiftData
import SwiftUI

private enum TaskListScope: String, CaseIterable, Identifiable {
    case all = "全部"
    case mineOnly = "指派給我"
    var id: String { rawValue }
}

struct MyTasksView: View {
    let projectCode: String
    @Environment(SessionStore.self) private var session
    @Environment(NetworkPathMonitor.self) private var network
    @Environment(\.modelContext) private var modelContext

    @Query private var pendingCreates: [PendingTaskCreateOutbox]

    @State private var tasks: [QualityTaskListItemDto] = []
    @State private var loadError: String?
    @State private var isLoading = false
    @State private var selectedRoute: TaskRoute?
    /// 與 Web 工作台總表對齊：預設「全部」；「指派給我」僅限執行對象為**個人**且 executorId 為本人（不含群組執行）。
    @State private var listScope: TaskListScope = .all
    @State private var statusTab: QualityTaskStatusTab = .inProgress
    @State private var filterStore = TaskManagementFilterStore()
    @State private var showFilter = false
    @State private var showDrawingPicker = false
    @State private var addTaskDrawing: QualityDrawingListItemDto?
    @State private var showSearch = false

    init(projectCode: String) {
        self.projectCode = projectCode
        let pc = projectCode
        _pendingCreates = Query(
            filter: #Predicate<PendingTaskCreateOutbox> { $0.projectCode == pc },
            sort: [SortDescriptor(\.enqueuedAt, order: .reverse)]
        )
    }

    private var pendingRowsForScope: [PendingTaskCreateOutbox] {
        let uid = session.currentUser?.id
        return pendingCreates.filter { row in
            if listScope == .mineOnly {
                return TaskCreateOutbox.pendingMatchesMineOnlyRow(row, userId: uid)
            }
            return true
        }
    }

    private var pendingAsListItems: [QualityTaskListItemDto] {
        pendingRowsForScope.map { TaskCreateOutbox.asListItem($0) }
    }

    /// 離線佇列列在最前，與已同步列表合併。
    private var mergedTasks: [QualityTaskListItemDto] {
        pendingAsListItems + tasks
    }

    private func tasksMatching(_ tab: QualityTaskStatusTab) -> [QualityTaskListItemDto] {
        mergedTasks.filter { tab.matches(status: $0.status) }
    }

    /// 目前選取之狀態分頁的任務（供空狀態 overlay 等使用）。
    private var currentTabTasks: [QualityTaskListItemDto] {
        tasksMatching(statusTab)
    }

    private func countForStatusTab(_ tab: QualityTaskStatusTab) -> Int {
        mergedTasks.filter { tab.matches(status: $0.status) }.count
    }

    private func groupedSections(for tab: QualityTaskStatusTab) -> [(key: String, title: String, tasks: [QualityTaskListItemDto])] {
        let rows = tasksMatching(tab)
        let dict = Dictionary(grouping: rows) { item in
            item.qualityDrawing?.id ?? "_"
        }
        return dict.keys.sorted().map { k in
            let sectionRows = dict[k] ?? []
            let title = sectionRows.first?.qualityDrawing?.name ?? (k == "_" ? "未指定樓層圖面" : "樓層")
            return (key: k, title: title, tasks: sectionRows.sorted { ($0.name ?? "") < ($1.name ?? "") })
        }
    }

    @ViewBuilder
    private func statusTabPage(for tab: QualityTaskStatusTab) -> some View {
        let sections = groupedSections(for: tab)
        List {
            if let loadError {
                Section {
                    Text(loadError)
                        .foregroundStyle(.red)
                        .font(.footnote)
                        .textSelection(.enabled)
                }
            }
            if !network.isConnected {
                Section {
                    Label("離線：顯示已快取之任務與尚未上傳的新增", systemImage: "wifi.slash")
                }
            }
            ForEach(sections, id: \.key) { section in
                Section {
                    ForEach(section.tasks) { t in
                        Button {
                            guard !t.id.hasPrefix("pending-") else { return }
                            selectedRoute = TaskRoute(id: t.id, qualityDrawingId: t.qualityDrawing?.id)
                        } label: {
                            QualityTaskListRow(
                                task: t,
                                showsPendingUploadIcon: t.id.hasPrefix("pending-")
                            )
                        }
                        .disabled(t.id.hasPrefix("pending-"))
                    }
                } header: {
                    Text("\(section.title)（\(section.tasks.count)）")
                }
            }
        }
        .dismissKeyboardOnScroll()
        .refreshable { await load(force: true) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                taskHero
                    .padding(.horizontal, 16)
                    .padding(.top, 10)
                    .padding(.bottom, 8)

                Button {
                    showSearch = true
                } label: {
                    NobleHallSearchPill(title: "搜尋任務、空間或執行人", systemImage: "magnifyingglass")
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.bottom, 4)
                .accessibilityLabel("搜尋任務")
                .accessibilityHint("開啟搜尋頁面")

                Picker("", selection: $statusTab) {
                    ForEach(QualityTaskStatusTab.allCases) { tab in
                        Text("\(tab.rawValue)（\(countForStatusTab(tab))）").tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

                TabView(selection: $statusTab) {
                    ForEach(QualityTaskStatusTab.allCases) { tab in
                        statusTabPage(for: tab)
                            .tag(tab)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(NobleHallTheme.warmBackground)
            }
            .nobleHallScreen()
            .navigationTitle("我的任務")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        ForEach(TaskListScope.allCases) { scope in
                            Button(scope.rawValue) {
                                guard listScope != scope else { return }
                                listScope = scope
                                Task { await load(force: true) }
                            }
                        }
                    } label: {
                        HStack(spacing: 3) {
                            Text(listScope.rawValue)
                            Image(systemName: "chevron.down")
                                .font(.caption2.weight(.semibold))
                        }
                        .font(.subheadline.weight(.medium))
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showFilter = true
                    } label: {
                        ZStack(alignment: .topTrailing) {
                            Image(systemName: "line.3.horizontal.decrease.circle")
                                .font(.body.weight(.medium))
                            if filterStore.activeConditionCount > 0 {
                                Text("\(min(filterStore.activeConditionCount, 9))")
                                    .font(.system(size: 10, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(4)
                                    .background(Color.red, in: Circle())
                                    .offset(x: 6, y: -6)
                            }
                        }
                    }
                    .accessibilityLabel("篩選")
                }
            }
            .navigationDestination(isPresented: $showFilter) {
                TaskManagementFilterRootView(projectCode: projectCode, store: filterStore)
            }
            .overlay {
                if !isLoading, currentTabTasks.isEmpty, loadError == nil {
                    ContentUnavailableView {
                        Label("\(statusTab.rawValue)沒有任務", systemImage: "checklist")
                    } description: {
                        Text(
                            emptyStateDescription
                        )
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                    }
                }
                if isLoading, tasks.isEmpty, pendingAsListItems.isEmpty { ProgressView() }
            }
            .task { await load(force: false) }
            .onChange(of: filterStore.revision) { _, _ in
                Task { await load(force: true) }
            }
            .onChange(of: network.isConnected) { _, online in
                guard online, let sid = session.spaceId else { return }
                Task {
                    await OutboxSync.flushPending(modelContext: modelContext, spaceId: sid, isOnline: true)
                    await load(force: true)
                }
            }
            .navigationDestination(isPresented: $showSearch) {
                TaskSearchView(projectCode: projectCode, tasks: mergedTasks)
            }
            .fullScreenCover(item: $selectedRoute) { route in
                TaskDetailView(
                    projectCode: projectCode,
                    taskId: route.id,
                    qualityDrawingIdHint: route.qualityDrawingId,
                    onClose: { selectedRoute = nil }
                )
            }
            .sheet(isPresented: $showDrawingPicker) {
                QualityDrawingPickerSheet(
                    projectCode: projectCode,
                    onSelect: { drawing in
                        showDrawingPicker = false
                        addTaskDrawing = drawing
                    },
                    onCancel: { showDrawingPicker = false }
                )
            }
            .fullScreenCover(item: $addTaskDrawing) { drawing in
                AddTaskPlanScreen(
                    projectCode: projectCode,
                    drawing: drawing,
                    onClose: { addTaskDrawing = nil },
                    onCreated: {
                        addTaskDrawing = nil
                        Task { await load(force: true) }
                    }
                )
            }
            .overlay(alignment: .bottomTrailing) {
                if !showFilter {
                    Button {
                        showDrawingPicker = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(.white)
                            .frame(width: 56, height: 56)
                            .background(NobleHallTheme.brandGold, in: Circle())
                            .shadow(color: NobleHallTheme.brandGold.opacity(0.28), radius: 10, y: 5)
                    }
                    .padding(.trailing, 20)
                    .padding(.bottom, 24)
                    .accessibilityLabel("新增任務")
                }
            }
        }
    }


    private var taskHero: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("NOBLE HALL")
                        .font(.caption.weight(.semibold))
                        .tracking(2)
                        .foregroundStyle(NobleHallTheme.brandGold)
                    Text("今日品質任務")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(NobleHallTheme.ink)
                    Text("專案 \(projectCode) · \(listScope.rawValue)")
                        .font(.subheadline)
                        .foregroundStyle(NobleHallTheme.secondaryInk)
                }
                Spacer(minLength: 0)
                NobleHallStatusPill(
                    title: network.isConnected ? "線上" : "離線",
                    systemImage: network.isConnected ? "wifi" : "wifi.slash",
                    tint: network.isConnected ? NobleHallTheme.success : NobleHallTheme.warning
                )
            }

            HStack(spacing: 10) {
                summaryMetric(title: statusTab.rawValue, value: "\(filteredTasks.count)")
                summaryMetric(title: "待上傳", value: "\(pendingAsListItems.count)")
                summaryMetric(title: "篩選", value: "\(filterStore.activeConditionCount)")
            }
        }
        .padding(18)
        .nobleHallCard(cornerRadius: 24)
    }

    private func summaryMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font(.title3.weight(.bold))
                .foregroundStyle(NobleHallTheme.ink)
            Text(title)
                .font(.caption.weight(.medium))
                .foregroundStyle(NobleHallTheme.secondaryInk)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(NobleHallTheme.brandGold.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private struct TaskRoute: Identifiable, Hashable {
        let id: String
        let qualityDrawingId: String?
    }

    private var emptyStateDescription: String {
        var parts: [String] = ["已套用「\(statusTab.rawValue)」"]
        if listScope == .mineOnly { parts.append("「指派給我」") }
        if filterStore.activeConditionCount > 0 { parts.append("進階篩選") }
        return parts.joined() + "，目前沒有符合的品質任務。"
    }

    private func load(force _: Bool) async {
        guard let sid = session.spaceId else {
            loadError = "缺少 Space（x-space-id），請重新登入。"
            return
        }
        let executorFilter: String? = (listScope == .mineOnly) ? session.currentUser?.id : nil
        if listScope == .mineOnly, executorFilter == nil {
            loadError = "無法篩選「指派給我」：未取得使用者 id。"
            return
        }
        loadError = nil
        if !network.isConnected {
            if let rows = try? LocalTaskCache.tasks(projectCode: projectCode, context: modelContext) {
                tasks = rows.map(Self.mapCached)
            }
            return
        }
        isLoading = true
        defer { isLoading = false }
        do {
            let loaded = try await QualityTaskAPI.allProjectTasks(
                projectCode: projectCode,
                spaceId: sid,
                filter: filterStore,
                executorIds: executorFilter.map { [$0] }
            )
            tasks = loaded
            try LocalTaskCache.replaceProjectTasks(loaded, projectCode: projectCode, context: modelContext)
            try modelContext.save()
            await prefetchTaskDetails(loaded, spaceId: sid)
        } catch {
            loadError = error.localizedDescription
            if let rows = try? LocalTaskCache.tasks(projectCode: projectCode, context: modelContext) {
                tasks = rows.map(Self.mapCached)
            }
        }
    }

    /// 連線載入列表後，背景快取任務詳情供離線執行（平面圖＋任務資料）。
    private func prefetchTaskDetails(_ items: [QualityTaskListItemDto], spaceId: String) async {
        for item in items where !item.id.hasPrefix("pending-") {
            let key = "\(projectCode)|\(item.id)"
            let existing = (try? modelContext.fetch(FetchDescriptor<CachedTaskDetailBlob>())) ?? []
            if existing.contains(where: { $0.cacheKey == key }) { continue }
            guard let detail = try? await QualityTaskAPI.taskDetail(
                projectCode: projectCode,
                taskId: item.id,
                spaceId: spaceId
            ) else { continue }
            try? LocalTaskCache.saveDetail(detail, projectCode: projectCode, taskId: item.id, context: modelContext)
            try? modelContext.save()
            try? await Task.sleep(nanoseconds: 60_000_000)
        }
    }

    private static func mapCached(_ row: CachedTaskRow) -> QualityTaskListItemDto {
        QualityTaskListItemDto(
            id: row.taskId,
            projectCode: row.projectCode,
            qualityDrawing: row.drawingId.map { QualityDrawingRefDto(id: $0, name: row.drawingName ?? "") },
            name: row.title,
            status: row.status,
            group: nil,
            room: nil,
            executor: nil,
            createdAt: row.createdAt
        )
    }
}

