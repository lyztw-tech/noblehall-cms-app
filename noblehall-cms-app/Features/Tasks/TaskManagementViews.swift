import SwiftUI

// MARK: - 任務管理根（平面圖 / 全部任務）

private enum TaskManagementListMode: String, CaseIterable, Identifiable {
    case floorPlan = "平面圖"
    case allTasks = "全部任務"
    var id: String { rawValue }

    var menuTitle: String {
        switch self {
        case .floorPlan: return "平面圖"
        case .allTasks: return "全部"
        }
    }
}

struct TaskManagementRootView: View {
    let projectCode: String

    @State private var listMode: TaskManagementListMode = .floorPlan
    @State private var filterStore = TaskManagementFilterStore()
    @State private var showFilter = false

    var body: some View {
        Group {
            switch listMode {
            case .floorPlan:
                TaskManagementFloorPlanListView(
                    projectCode: projectCode,
                    filterStore: filterStore,
                    showFilter: $showFilter
                )
            case .allTasks:
                TaskManagementAllTasksView(
                    projectCode: projectCode,
                    filterStore: filterStore,
                    showFilter: $showFilter
                )
            }
        }
        .navigationTitle("任務管理")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    ForEach(TaskManagementListMode.allCases) { mode in
                        Button(mode.rawValue) {
                            listMode = mode
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: listMode == .floorPlan ? "map.fill" : "checklist")
                        Text(listMode.menuTitle)
                        Image(systemName: "chevron.down")
                            .font(.caption2.weight(.semibold))
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(NobleHallTheme.brandGold)
                }
            }
        }
        .navigationDestination(isPresented: $showFilter) {
            TaskManagementFilterRootView(projectCode: projectCode, store: filterStore)
        }
    }
}

// MARK: - Routes

struct TaskManagementDrawingRoute: Hashable {
    let id: String
    let name: String
    let taskCount: Int
    let counts: QualityDrawingTaskCountByStatusDto
}

struct TaskManagementStatusRoute: Hashable {
    let drawingId: String
    let drawingName: String
    let filter: TaskManagementStatusFilter
}

// MARK: - 全部任務（跨平面圖）

struct TaskManagementAllTasksView: View {
    let projectCode: String
    var filterStore: TaskManagementFilterStore
    @Binding var showFilter: Bool

    @Environment(SessionStore.self) private var session
    @Environment(NetworkPathMonitor.self) private var network

    @State private var tasks: [QualityTaskListItemDto] = []
    @State private var loadError: String?
    @State private var isLoading = false
    @State private var selectedRoute: TaskDetailRoute?
    @State private var showSearch = false

    private var grouped: [(key: String, title: String, tasks: [QualityTaskListItemDto])] {
        let dict = Dictionary(grouping: tasks) { $0.qualityDrawing?.id ?? "_" }
        return dict.keys.sorted().map { key in
            let rows = dict[key] ?? []
            let title = rows.first?.qualityDrawing?.name ?? (key == "_" ? "未指定樓層圖面" : "樓層")
            return (key: key, title: title, tasks: rows.sorted { ($0.name ?? "") < ($1.name ?? "") })
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if isLoading, tasks.isEmpty {
                    ProgressView("載入任務…")
                } else if let loadError, tasks.isEmpty {
                    ContentUnavailableView("無法載入", systemImage: "exclamationmark.triangle", description: Text(loadError))
                } else {
                    List {
                        if !network.isConnected {
                            Section {
                                HStack {
                                    NobleHallOfflineTag(text: "僅快取")
                                    Spacer(minLength: 0)
                                }
                                .nobleHallOfflineListTagRow()
                            }
                        }
                        ForEach(grouped, id: \.key) { section in
                            Section {
                                ForEach(section.tasks) { task in
                                    Button {
                                        selectedRoute = TaskDetailRoute(id: task.id)
                                    } label: {
                                        QualityTaskListRow(task: task)
                                    }
                                }
                            } header: {
                                Text("\(section.title)（\(section.tasks.count)）")
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                    .background(NobleHallTheme.warmBackground)
                    .dismissKeyboardOnScroll()
                }
            }
        }
        .nobleHallScreen()
        .overlay {
            if !isLoading, tasks.isEmpty, loadError == nil {
                ContentUnavailableView {
                    Label("沒有任務", systemImage: "checklist")
                } description: {
                    Text(filterStore.activeConditionCount > 0
                        ? "目前沒有符合篩選條件的任務。"
                        : "目前沒有品質任務。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .nobleHallScreen()
        .refreshable { await load() }
        .task { await load() }
        .onChange(of: filterStore.revision) { _, _ in
            Task { await load() }
        }
        .taskManagementSearchFilterToolbar(
            showSearch: $showSearch,
            showFilter: $showFilter,
            filterActiveCount: filterStore.activeConditionCount,
            searchAccessibilityLabel: "搜尋任務"
        )
        .sheet(isPresented: $showSearch) {
            TaskSearchView(projectCode: projectCode, tasks: tasks)
        }
        .fullScreenCover(item: $selectedRoute) { route in
            TaskDetailView(
                projectCode: projectCode,
                taskId: route.id,
                onClose: { selectedRoute = nil }
            )
        }
        .dismissKeyboardOnTapOutside()
    }

    private func load() async {
        guard let sid = session.spaceId else {
            loadError = "缺少 Space，請重新登入。"
            return
        }
        guard network.isConnected else {
            loadError = "請連線後載入任務。"
            return
        }
        loadError = nil
        isLoading = true
        defer { isLoading = false }
        do {
            tasks = try await QualityTaskAPI.allProjectTasks(
                projectCode: projectCode,
                spaceId: sid,
                filter: filterStore
            )
        } catch {
            loadError = error.localizedDescription
        }
    }

    private struct TaskDetailRoute: Identifiable, Hashable {
        let id: String
    }
}

// MARK: - 第一層：平面圖列表

struct TaskManagementFloorPlanListView: View {
    let projectCode: String
    var filterStore: TaskManagementFilterStore
    @Binding var showFilter: Bool

    @Environment(SessionStore.self) private var session
    @Environment(NetworkPathMonitor.self) private var network

    @State private var drawings: [QualityDrawingListItemDto] = []
    @State private var loadError: String?
    @State private var isLoading = false
    @State private var showSearch = false

    private var visibleDrawings: [QualityDrawingListItemDto] {
        guard let did = filterStore.qualityDrawingId else { return drawings }
        return drawings.filter { $0.id == did }
    }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                if isLoading, drawings.isEmpty {
                    ProgressView("載入平面圖…")
                } else if let loadError, drawings.isEmpty {
                    ContentUnavailableView("無法載入", systemImage: "exclamationmark.triangle", description: Text(loadError))
                } else if visibleDrawings.isEmpty {
                    ContentUnavailableView(
                        filterStore.qualityDrawingId != nil ? "沒有符合的平面圖" : "尚無平面圖",
                        systemImage: "map"
                    )
                } else {
                    List(visibleDrawings) { item in
                        NavigationLink(value: route(for: item)) {
                            DrawingListRow(item: item)
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                    .background(NobleHallTheme.warmBackground)
                    .dismissKeyboardOnScroll()
                }
            }
        }
        .refreshable { await load() }
        .task { await load() }
        .taskManagementSearchFilterToolbar(
            showSearch: $showSearch,
            showFilter: $showFilter,
            filterActiveCount: filterStore.activeConditionCount,
            searchAccessibilityLabel: "搜尋平面圖"
        )
        // 平面圖搜尋須放在**獨立** `NavigationStack`（例如 sheet）內並自行註冊
        // `navigationDestination(for: TaskManagementDrawingRoute)`：
        // 若僅以 `navigationDestination(isPresented:)` 疊在列表同一層 stack 上，搜尋頁裡的
        // `NavigationLink(value:)` 往往無法觸發父層的 value destination，點選後仍停在搜尋畫面。
        .sheet(isPresented: $showSearch) {
            NavigationStack {
                DrawingSearchView(
                    projectCode: projectCode,
                    drawings: drawings,
                    filterStore: filterStore
                )
                .navigationDestination(for: TaskManagementDrawingRoute.self) { route in
                    TaskManagementStatusBoardView(projectCode: projectCode, route: route, filterStore: filterStore)
                }
            }
            .presentationDragIndicator(.visible)
        }
        .navigationDestination(for: TaskManagementDrawingRoute.self) { route in
            TaskManagementStatusBoardView(projectCode: projectCode, route: route, filterStore: filterStore)
        }
        .dismissKeyboardOnTapOutside()
    }

    private func route(for item: QualityDrawingListItemDto) -> TaskManagementDrawingRoute {
        TaskManagementDrawingRoute(
            id: item.id,
            name: item.drawing.name,
            taskCount: item.taskCount ?? 0,
            counts: item.taskCountByStatus ?? .zero
        )
    }

    private func load() async {
        guard let sid = session.spaceId else {
            loadError = "缺少 Space，請重新登入。"
            return
        }
        guard network.isConnected else {
            loadError = "請連線後再使用任務管理。"
            return
        }
        loadError = nil
        isLoading = true
        defer { isLoading = false }
        do {
            drawings = try await QualityTaskAPI.allQualityDrawings(projectCode: projectCode, spaceId: sid)
        } catch {
            loadError = error.localizedDescription
        }
    }
}

// MARK: - 平面圖搜尋

struct DrawingSearchView: View {
    let projectCode: String
    let drawings: [QualityDrawingListItemDto]
    var filterStore: TaskManagementFilterStore

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var results: [QualityDrawingListItemDto] {
        QualityDrawingSearch.filter(drawings, query: query)
    }

    var body: some View {
        NobleHallNativeSearchScreen(
            query: $query,
            prompt: "樓層、圖面名稱",
            emptyTitle: "搜尋平面圖",
            emptyDescription: "輸入樓層或圖面名稱",
            onCancel: closeSearch
        ) {
            if results.isEmpty {
                ContentUnavailableView("找不到符合的平面圖", systemImage: "magnifyingglass")
            } else {
                List {
                    ForEach(results) { item in
                        NavigationLink(value: drawingRoute(for: item)) {
                            DrawingListRow(item: item)
                        }
                    }
                }
                .listStyle(.plain)
                .dismissKeyboardOnScroll()
            }
        }
        // 平面圖詳情之 `navigationDestination(for: TaskManagementDrawingRoute)` 由**外層**
        // `TaskManagementFloorPlanListView`（列表直進）或 **sheet 內** `NavigationStack`（搜尋進入）
        // 註冊；勿在此再掛同一型別，否則同一 stack 會重複註冊而觸發 Runtime 警告。
    }

    private func closeSearch() {
        query = ""
        dismiss()
    }

    private func drawingRoute(for item: QualityDrawingListItemDto) -> TaskManagementDrawingRoute {
        TaskManagementDrawingRoute(
            id: item.id,
            name: item.drawing.name,
            taskCount: item.taskCount ?? 0,
            counts: item.taskCountByStatus ?? .zero
        )
    }
}

private struct DrawingListRow: View {
    let item: QualityDrawingListItemDto

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(NobleHallTheme.brandGold.opacity(0.12))
                Image(systemName: "doc.richtext.fill")
                    .foregroundStyle(NobleHallTheme.brandGold)
            }
            .frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 5) {
                Text(item.drawing.name)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(NobleHallTheme.ink)
                NobleHallStatusPill(title: "共 \(item.taskCount ?? 0) 項任務", systemImage: "checklist", tint: NobleHallTheme.brandGold)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
    }
}

// MARK: - 第二層：狀態卡片

struct TaskManagementStatusBoardView: View {
    let projectCode: String
    let route: TaskManagementDrawingRoute
    var filterStore: TaskManagementFilterStore

    private let columns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(route.name)
                        .font(.title2.weight(.bold))
                    Text("共 \(route.taskCount) 項任務")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 8)

                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(TaskManagementStatusFilter.allCases) { filter in
                        let count = filter.count(in: route.counts)
                        NavigationLink(value: TaskManagementStatusRoute(
                            drawingId: route.id,
                            drawingName: route.name,
                            filter: filter
                        )) {
                            TaskManagementStatusCard(title: filter.title, count: count, tint: filter.tint)
                        }
                        .buttonStyle(.plain)
                        .disabled(count == 0)
                        .opacity(count == 0 ? 0.45 : 1)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
        }
        .background(NobleHallTheme.warmBackground)
        .navigationTitle(route.name)
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: TaskManagementStatusRoute.self) { statusRoute in
            TaskManagementStatusTaskListView(
                projectCode: projectCode,
                route: statusRoute,
                filterStore: filterStore
            )
        }
        .dismissKeyboardOnTapOutside()
    }
}

private struct TaskManagementStatusCard: View {
    let title: String
    let count: Int
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
            Text("\(count)")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
            Text("項任務")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(NobleHallTheme.cardBackground, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(tint.opacity(0.25), lineWidth: 1)
        )
    }
}

// MARK: - 第三層：狀態任務列表

struct TaskManagementStatusTaskListView: View {
    let projectCode: String
    let route: TaskManagementStatusRoute
    var filterStore: TaskManagementFilterStore

    @Environment(SessionStore.self) private var session
    @Environment(NetworkPathMonitor.self) private var network

    @State private var tasks: [QualityTaskListItemDto] = []
    @State private var loadError: String?
    @State private var isLoading = false
    @State private var selectedRoute: TaskDetailRoute?

    var body: some View {
        Group {
            if isLoading, tasks.isEmpty {
                ProgressView("載入任務…")
            } else if let loadError, tasks.isEmpty {
                ContentUnavailableView("無法載入", systemImage: "exclamationmark.triangle", description: Text(loadError))
            } else if tasks.isEmpty {
                ContentUnavailableView {
                    Label("沒有任務", systemImage: "checklist")
                } description: {
                    Text("此平面圖在「\(route.filter.title)」目前沒有任務。")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                List(tasks) { task in
                    Button {
                        selectedRoute = TaskDetailRoute(id: task.id)
                    } label: {
                        QualityTaskListRow(task: task)
                    }
                }
                .listStyle(.insetGrouped)
                .dismissKeyboardOnScroll()
            }
        }
        .navigationTitle(route.filter.title)
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await load() }
        .task { await load() }
        .onChange(of: filterStore.revision) { _, _ in
            Task { await load() }
        }
        .fullScreenCover(item: $selectedRoute) { route in
            TaskDetailView(
                projectCode: projectCode,
                taskId: route.id,
                onClose: { selectedRoute = nil }
            )
        }
    }

    private struct TaskDetailRoute: Identifiable, Hashable {
        let id: String
    }

    private func load() async {
        guard let sid = session.spaceId else {
            loadError = "缺少 Space，請重新登入。"
            return
        }
        guard network.isConnected else {
            loadError = "請連線後再載入任務。"
            return
        }
        loadError = nil
        isLoading = true
        defer { isLoading = false }
        do {
            let mergedStatuses: [String] = {
                if filterStore.statuses.isEmpty { return route.filter.apiStatuses }
                let card = Set(route.filter.apiStatuses)
                let picked = filterStore.statuses.filter { card.contains($0) }
                return picked.isEmpty ? route.filter.apiStatuses : picked
            }()
            tasks = try await QualityTaskAPI.allProjectTasks(
                projectCode: projectCode,
                spaceId: sid,
                filter: filterStore,
                qualityDrawingId: route.drawingId,
                statuses: mergedStatuses
            )
            tasks.sort { ($0.name ?? "") < ($1.name ?? "") }
        } catch {
            loadError = error.localizedDescription
        }
    }
}
