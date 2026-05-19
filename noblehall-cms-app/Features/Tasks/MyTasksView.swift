import SwiftData
import SwiftUI

private struct MyTasksHeaderChromeHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

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
    /// 與 Web 任務管理總表對齊：預設「全部」；「指派給我」僅限執行對象為**個人**且 executorId 為本人（不含群組執行）。
    @State private var listScope: TaskListScope = .all
    @State private var statusTab: QualityTaskStatusTab = .inProgress
    @State private var filterStore = TaskManagementFilterStore()
    @State private var showFilter = false
    @State private var showDrawingPicker = false
    @State private var addTaskDrawing: QualityDrawingListItemDto?
    @State private var showSearch = false
    @State private var headerChromeHeight: CGFloat = 52

    private static let offlineStatusDetail = "可瀏覽快取，連線後自動上傳"

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
            ForEach(sections, id: \.key) { section in
                Section {
                    ForEach(section.tasks) { t in
                        Button {
                            guard !t.id.hasPrefix("pending-") else { return }
                            selectedRoute = TaskRoute(id: t.id, qualityDrawingId: t.qualityDrawing?.id)
                        } label: {
                            QualityTaskListRow(
                                task: t,
                                showsDrawingAndStatus: false,
                                showsPendingUploadIcon: t.id.hasPrefix("pending-"),
                                showsExecutor: listScope == .all
                            )
                        }
                        .disabled(t.id.hasPrefix("pending-"))
                    }
                } header: {
                    Text("\(section.title)（\(section.tasks.count)）")
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .scrollClipDisabled()
        .contentMargins(.top, headerChromeHeight, for: .scrollContent)
        .contentMargins(.bottom, 8, for: .scrollContent)
        .dismissKeyboardOnScroll()
        .refreshable { await load(force: true) }
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 0) {
                        ForEach(QualityTaskStatusTab.allCases) { tab in
                            statusTabPage(for: tab)
                                .containerRelativeFrame(.horizontal)
                                .id(tab)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
                .scrollIndicators(.hidden)
                .scrollPosition(id: statusTabScrollBinding)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                myTasksHeaderChrome
            }
            .nobleHallScreen()
            .onPreferenceChange(MyTasksHeaderChromeHeightKey.self) { height in
                if height > 0 { headerChromeHeight = height }
            }
            .navigationTitle("我的任務")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(NobleHallTheme.warmBackground, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        ForEach(TaskListScope.allCases) { scope in
                            Button {
                                guard listScope != scope else { return }
                                listScope = scope
                                Task { await load(force: true) }
                            } label: {
                                HStack {
                                    Text(scope.rawValue)
                                    Spacer(minLength: 8)
                                    if listScope == scope {
                                        Image(systemName: "checkmark")
                                            .font(.subheadline.weight(.semibold))
                                    }
                                }
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
                ToolbarItemGroup(placement: .topBarTrailing) {
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

                    Button {
                        showSearch = true
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }
                    .accessibilityLabel("搜尋任務")
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
                    .padding(.top, headerChromeHeight)
                }
                if isLoading, tasks.isEmpty, pendingAsListItems.isEmpty {
                    ProgressView()
                        .padding(.top, headerChromeHeight)
                }
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
            .sheet(isPresented: $showSearch) {
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


    /// `scrollPosition(id:)` 需要 `Binding<Hashable?>`，與非 optional 的 `statusTab` 橋接。
    private var statusTabScrollBinding: Binding<QualityTaskStatusTab?> {
        Binding(
            get: { statusTab },
            set: { if let value = $0 { statusTab = value } }
        )
    }

    /// 浮於列表上方；暖色底擋住捲動內容。離線時於分頁上方顯示提示。
    private var myTasksHeaderChrome: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !network.isConnected {
                NobleHallOfflineTag(
                    prefix: "離線中",
                    detail: Self.offlineStatusDetail
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Picker("", selection: $statusTab) {
                ForEach(QualityTaskStatusTab.allCases) { tab in
                    Text("\(tab.rawValue)（\(countForStatusTab(tab))）").tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .background {
            NobleHallTheme.warmBackground
                .ignoresSafeArea(edges: .top)
        }
        .background {
            GeometryReader { proxy in
                Color.clear.preference(key: MyTasksHeaderChromeHeightKey.self, value: proxy.size.height)
            }
        }
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
            loadError = error.userFacingMessage
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

