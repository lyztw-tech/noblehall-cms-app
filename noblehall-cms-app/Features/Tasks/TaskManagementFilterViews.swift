import SwiftUI

// MARK: - 篩選入口（第一層：條件列表 → 第二層：選項／輸入）

struct TaskManagementFilterRootView: View {
    let projectCode: String
    @Bindable var store: TaskManagementFilterStore

    @Environment(\.dismiss) private var dismiss
    @Environment(SessionStore.self) private var session

    @State private var drawings: [QualityDrawingListItemDto] = []
    @State private var members: [ProjectMemberDto] = []
    @State private var categories: [DropdownOptionItemDto] = []
    @State private var groupOptions: [TaskManagementFilterOption] = []
    @State private var roomOptions: [TaskManagementFilterOption] = []
    @State private var loadError: String?

    var body: some View {
        List {
            if let loadError {
                Section {
                    Text(loadError).font(.footnote).foregroundStyle(.red)
                }
            }
            Section {
                ForEach(TaskManagementFilterField.allCases) { field in
                    NavigationLink {
                        filterDetail(for: field)
                    } label: {
                        HStack {
                            Text(field.title)
                            Spacer()
                            Text(
                                store.displaySummary(
                                    field: field,
                                    drawings: drawings,
                                    members: members,
                                    categories: categories,
                                    groups: groupOptions,
                                    rooms: roomOptions
                                )
                            )
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .toolbar(.hidden, for: .tabBar)
        .navigationTitle("篩選條件")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("清除") {
                    store.reset()
                    groupOptions = []
                    roomOptions = []
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("套用") {
                    store.bump()
                    dismiss()
                }
                .fontWeight(.semibold)
            }
        }
        .task(id: store.qualityDrawingId) {
            await reloadGroupAndRoomOptions()
        }
        .task { await loadMeta() }
    }

    @ViewBuilder
    private func filterDetail(for field: TaskManagementFilterField) -> some View {
        filterDetailContent(for: field)
            .toolbar(.hidden, for: .tabBar)
    }

    @ViewBuilder
    private func filterDetailContent(for field: TaskManagementFilterField) -> some View {
        switch field {
        case .qualityDrawing:
            TaskManagementFilterDrawingPickerView(
                drawings: drawings,
                selection: Binding(
                    get: { store.qualityDrawingId },
                    set: {
                        store.qualityDrawingId = $0
                        store.groupIds = []
                        store.roomIds = []
                    }
                ),
                onChange: {
                    Task { await reloadGroupAndRoomOptions() }
                }
            )
        case .status:
            TaskManagementFilterMultiSelectView(
                title: field.title,
                options: TaskManagementFilterCatalog.statusOptions,
                selection: $store.statuses
            )
        case .search:
            TaskManagementFilterTextInputView(text: $store.search, placeholder: "關鍵字搜尋")
        case .group:
            TaskManagementFilterMultiSelectView(
                title: field.title,
                options: groupOptions,
                selection: $store.groupIds,
                emptyHint: store.qualityDrawingId == nil ? "請先在「平面圖」選擇圖面" : "此圖面尚無群組"
            )
            .onChange(of: store.groupIds) { _, ids in
                if ids.count != 1 {
                    store.roomIds = []
                }
                Task { await reloadGroupAndRoomOptions() }
            }
        case .room:
            TaskManagementFilterMultiSelectView(
                title: field.title,
                options: roomOptions,
                selection: $store.roomIds,
                emptyHint: store.groupIds.count != 1 ? "請先在「群組」選擇一個群組" : "此群組尚無空間"
            )
        case .category:
            TaskManagementFilterMultiSelectView(
                title: field.title,
                options: categories.map { TaskManagementFilterOption(id: $0.id, label: $0.value) },
                selection: $store.categoryIds,
                emptyHint: "尚無類別選項"
            )
        case .priority:
            TaskManagementFilterMultiSelectView(
                title: field.title,
                options: TaskManagementFilterCatalog.priorityOptions,
                selection: $store.priorities
            )
        case .createdDate:
            TaskManagementFilterDateRangeView(
                title: field.title,
                from: $store.createdFrom,
                to: $store.createdTo
            )
        case .dueDate:
            TaskManagementFilterDateRangeView(
                title: field.title,
                from: $store.dueFrom,
                to: $store.dueTo
            )
        case .executor:
            TaskManagementFilterMemberSelectView(
                title: field.title,
                members: members,
                selection: $store.executorIds
            )
        case .reviewer:
            TaskManagementFilterMemberSelectView(
                title: field.title,
                members: members,
                selection: $store.reviewerIds
            )
        }
    }

    private func loadMeta() async {
        guard let sid = session.spaceId else {
            loadError = "缺少 Space。"
            return
        }
        loadError = nil
        do {
            async let d = QualityTaskAPI.allQualityDrawings(projectCode: projectCode, spaceId: sid)
            async let m = QualityTaskAPI.allProjectMembers(projectCode: projectCode, spaceId: sid)
            let (drawList, memList) = try await (d, m)
            drawings = drawList
            members = memList
            if let project = try? await ProjectAPI.projectDetail(projectCode: projectCode, spaceId: sid),
               let cats = try? await QualityTaskAPI.categoryOptions(projectId: project.id, spaceId: sid) {
                categories = cats.options
            }
            await reloadGroupAndRoomOptions()
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func reloadGroupAndRoomOptions() async {
        guard let sid = session.spaceId, let qd = store.qualityDrawingId else {
            groupOptions = []
            roomOptions = []
            return
        }
        do {
            let points = try await QualityTaskAPI.roomPoints(
                projectCode: projectCode,
                qualityDrawingId: qd,
                spaceId: sid
            )
            var groupMap: [String: String] = [:]
            for p in points {
                guard let gid = p.groupId, !gid.isEmpty else { continue }
                if groupMap[gid] == nil {
                    groupMap[gid] = p.name
                }
            }
            groupOptions = groupMap.map { TaskManagementFilterOption(id: $0.key, label: $0.value) }
                .sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }

            if store.groupIds.count == 1, let gid = store.groupIds.first {
                roomOptions = points
                    .filter { $0.groupId == gid && !$0.id.hasPrefix("qt-hh:") }
                    .map { TaskManagementFilterOption(id: $0.id, label: $0.name) }
                    .sorted { $0.label.localizedStandardCompare($1.label) == .orderedAscending }
            } else {
                roomOptions = []
            }
        } catch {
            groupOptions = []
            roomOptions = []
        }
    }
}

// MARK: - 第二層：平面圖

private struct TaskManagementFilterDrawingPickerView: View {
    let drawings: [QualityDrawingListItemDto]
    @Binding var selection: String?
    var onChange: () -> Void

    var body: some View {
        List {
            Button {
                selection = nil
                onChange()
            } label: {
                HStack {
                    Text("全部平面圖")
                    Spacer()
                    if selection == nil {
                        Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                    }
                }
            }
            .foregroundStyle(.primary)
            ForEach(drawings) { item in
                Button {
                    selection = item.id
                    onChange()
                } label: {
                    HStack {
                        Text(item.drawing.name)
                        Spacer()
                        if selection == item.id {
                            Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                        }
                    }
                }
                .foregroundStyle(.primary)
            }
        }
        .navigationTitle("平面圖")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 第二層：多選

private struct TaskManagementFilterMultiSelectView: View {
    let title: String
    let options: [TaskManagementFilterOption]
    @Binding var selection: [String]
    var emptyHint: String = "尚無選項"

    var body: some View {
        Group {
            if options.isEmpty {
                ContentUnavailableView("無法選擇", systemImage: "line.3.horizontal.decrease.circle", description: Text(emptyHint))
            } else {
                List {
                    Button {
                        selection = []
                    } label: {
                        HStack {
                            Text("全部")
                            Spacer()
                            if selection.isEmpty {
                                Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                            }
                        }
                    }
                    .foregroundStyle(.primary)
                    ForEach(options) { opt in
                        Button {
                            toggle(opt.id)
                        } label: {
                            HStack {
                                Text(opt.label)
                                Spacer()
                                if selection.contains(opt.id) {
                                    Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                                }
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func toggle(_ id: String) {
        if selection.contains(id) {
            selection.removeAll { $0 == id }
        } else {
            selection.append(id)
        }
    }
}

// MARK: - 第二層：文字

private struct TaskManagementFilterTextInputView: View {
    @Binding var text: String
    let placeholder: String

    var body: some View {
        Form {
            Section {
                TextField(placeholder, text: $text, axis: .vertical)
                    .lineLimit(2 ... 4)
            }
        }
        .dismissKeyboardOnScroll()
        .keyboardDoneToolbar()
        .navigationTitle("描述")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 第二層：日期區間

private struct TaskManagementFilterDateRangeView: View {
    let title: String
    @Binding var from: Date?
    @Binding var to: Date?

    var body: some View {
        Form {
            Section("起日") {
                Toggle("設定起日", isOn: Binding(
                    get: { from != nil },
                    set: { on in from = on ? (from ?? Date()) : nil }
                ))
                if from != nil {
                    DatePicker("起日", selection: Binding(
                        get: { from ?? Date() },
                        set: { from = $0 }
                    ), displayedComponents: [.date])
                }
            }
            Section("迄日") {
                Toggle("設定迄日", isOn: Binding(
                    get: { to != nil },
                    set: { on in to = on ? (to ?? Date()) : nil }
                ))
                if to != nil {
                    DatePicker("迄日", selection: Binding(
                        get: { to ?? Date() },
                        set: { to = $0 }
                    ), displayedComponents: [.date])
                }
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - 第二層：成員多選

private struct TaskManagementFilterMemberSelectView: View {
    let title: String
    let members: [ProjectMemberDto]
    @Binding var selection: [String]

    private var sortedMembers: [ProjectMemberDto] {
        members.sorted {
            ($0.user.displayName ?? $0.user.username ?? "")
                .localizedStandardCompare($1.user.displayName ?? $1.user.username ?? "") == .orderedAscending
        }
    }

    var body: some View {
        List {
            Button {
                selection = []
            } label: {
                HStack {
                    Text("全部")
                    Spacer()
                    if selection.isEmpty {
                        Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                    }
                }
            }
            .foregroundStyle(.primary)
            ForEach(sortedMembers, id: \.user.id) { m in
                let uid = m.user.id
                Button {
                    toggle(uid)
                } label: {
                    HStack {
                        Text(m.user.displayName ?? m.user.username ?? uid)
                        Spacer()
                        if selection.contains(uid) {
                            Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                        }
                    }
                }
                .foregroundStyle(.primary)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func toggle(_ id: String) {
        if selection.contains(id) {
            selection.removeAll { $0 == id }
        } else {
            selection.append(id)
        }
    }
}
