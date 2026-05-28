import SwiftData
import SwiftUI

/// 任務詳情內第二層 bottom sheet：編輯任務欄位（PATCH quality-tasks）。
struct TaskDetailTaskEditSheet: View {
    let projectCode: String
    let qualityDrawingId: String
    let taskId: String
    let spaceId: String
    let initialTask: QualityTaskDto
    /// 與 Web assignment-only / `basicInfoNonAssignmentFieldsLocked` 對齊：僅能改審查人與執行對象。
    let assignmentFieldsOnly: Bool
    var onCancel: () -> Void
    var onSaved: () async -> Void

    @Environment(\.modelContext) private var modelContext

    @State private var name: String
    @State private var description: String
    @State private var priority: String
    @State private var includeDueDate: Bool
    @State private var dueDate: Date
    @State private var categoryId: String
    @State private var reviewerId: String
    @State private var executorKind: ExecutorKind
    @State private var executorUserId: String
    @State private var executorGroupId: String
    @State private var formCacheLoaded = false
    @State private var categories: [DropdownOptionItemDto] = []
    @State private var members: [ProjectMemberDto] = []
    @State private var groups: [ProjectGroupDto] = []
    @State private var saveError: String?
    @State private var isSaving = false

    private let initialHadDue: Bool
    private static let maxNameLength = 20
    private static let maxDescriptionLength = 100

    private enum ExecutorKind: String, CaseIterable, Identifiable {
        case none = "未指派"
        case user = "成員"
        case group = "群組"
        var id: String { rawValue }
    }

    init(
        projectCode: String,
        qualityDrawingId: String,
        taskId: String,
        spaceId: String,
        initialTask: QualityTaskDto,
        assignmentFieldsOnly: Bool,
        onCancel: @escaping () -> Void,
        onSaved: @escaping () async -> Void
    ) {
        self.projectCode = projectCode
        self.qualityDrawingId = qualityDrawingId
        self.taskId = taskId
        self.spaceId = spaceId
        self.initialTask = initialTask
        self.assignmentFieldsOnly = assignmentFieldsOnly
        self.onCancel = onCancel
        self.onSaved = onSaved

        _name = State(initialValue: initialTask.name)
        _description = State(initialValue: initialTask.description ?? "")

        let pr = initialTask.priority?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        let resolvedPriority = ["low", "medium", "high"].contains(pr) ? pr : "medium"
        _priority = State(initialValue: resolvedPriority)

        let hadDue = initialTask.dueDate != nil
        initialHadDue = hadDue
        _includeDueDate = State(initialValue: hadDue)
        _dueDate = State(initialValue: initialTask.dueDate ?? Date())

        _categoryId = State(initialValue: initialTask.categoryId ?? "")
        _reviewerId = State(initialValue: initialTask.reviewer?.id ?? "")
        let initialExecutorType = initialTask.executorType?.lowercased()
        if initialExecutorType == "user", let id = initialTask.executorId, !id.isEmpty {
            _executorKind = State(initialValue: .user)
            _executorUserId = State(initialValue: id)
            _executorGroupId = State(initialValue: "")
        } else if initialExecutorType == "group", let id = initialTask.executorId, !id.isEmpty {
            _executorKind = State(initialValue: .group)
            _executorUserId = State(initialValue: "")
            _executorGroupId = State(initialValue: id)
        } else {
            _executorKind = State(initialValue: .none)
            _executorUserId = State(initialValue: "")
            _executorGroupId = State(initialValue: "")
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                if let saveError, !saveError.isEmpty {
                    Section {
                        Text(saveError)
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                }
                if assignmentFieldsOnly {
                    Section {
                        Text(
                            "目前僅能修改審查人與執行對象；其他欄位已鎖定。"
                        )
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }
                }
                Section("任務內容") {
                    TextField("任務名稱", text: $name)
                        .disabled(assignmentFieldsOnly)
                    Text("\(name.count)/\(Self.maxNameLength)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(name.count > Self.maxNameLength ? .red : .secondary)
                    TextField("說明", text: $description, axis: .vertical)
                        .lineLimit(3 ... 8)
                        .disabled(assignmentFieldsOnly)
                    Text("\(description.count)/\(Self.maxDescriptionLength)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(description.count > Self.maxDescriptionLength ? .red : .secondary)
                    Picker("優先級", selection: $priority) {
                        Text("低").tag("low")
                        Text("中").tag("medium")
                        Text("高").tag("high")
                    }
                    .disabled(assignmentFieldsOnly)
                }
                Section("到期日") {
                    Toggle("設定到期日", isOn: $includeDueDate)
                        .disabled(assignmentFieldsOnly)
                    if includeDueDate {
                        DatePicker("到期日", selection: $dueDate, displayedComponents: [.date, .hourAndMinute])
                            .disabled(assignmentFieldsOnly)
                    }
                }
                if formCacheLoaded && (!categories.isEmpty || !members.isEmpty || !groups.isEmpty) {
                    Section("分類與審查") {
                        if !categories.isEmpty {
                            Picker("類別", selection: $categoryId) {
                                Text("（不選）").tag("")
                                ForEach(categories) { c in
                                    Text(c.value).tag(c.id)
                                }
                            }
                            .disabled(assignmentFieldsOnly)
                        }
                        Picker("審查人 *", selection: $reviewerId) {
                            Text("請選擇").tag("")
                            ForEach(reviewerOptions, id: \.user.id) { m in
                                Text(memberLabel(m))
                                    .tag(m.user.id)
                            }
                        }
                    }
                    Section {
                        Picker("執行對象", selection: $executorKind) {
                            ForEach(ExecutorKind.allCases) { kind in
                                Text(kind.rawValue).tag(kind)
                            }
                        }
                        .onChange(of: executorKind) { _, newValue in
                            if newValue != .user { executorUserId = "" }
                            if newValue != .group { executorGroupId = "" }
                        }
                        if executorKind == .user {
                            Picker("執行人（工地人員）", selection: $executorUserId) {
                                Text("請選擇").tag("")
                                ForEach(siteStaffMembers, id: \.user.id) { m in
                                    Text(memberLabel(m)).tag(m.user.id)
                                }
                            }
                        } else if executorKind == .group {
                            Picker("執行群組", selection: $executorGroupId) {
                                Text("請選擇").tag("")
                                ForEach(groupsWithOwner) { g in
                                    Text(g.name).tag(g.id)
                                }
                            }
                        }
                    } header: {
                        Text("執行對象")
                    } footer: {
                        Text("執行人僅可選「工地人員」；執行群組僅顯示已有負責人的群組。")
                    }
                } else if formCacheLoaded {
                    Section {
                        Text(
                            assignmentFieldsOnly
                                ? "快取中尚無專案成員或群組，無法變更審查人與執行對象。請稍後再試或至網頁任務管理處理。"
                                : "快取中尚無可選的類別、專案成員或群組，無法在此變更完整任務資料。"
                        )
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }
                } else {
                    Section {
                        Text(
                            assignmentFieldsOnly
                                ? "未載入成員／群組快取：目前無法變更審查人與執行對象。請連線後稍後再試。"
                                : "未載入成員／類別／群組快取：僅可編輯名稱、說明、優先級與到期日。建立任務或稍後再試可載入完整選項。"
                        )
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }
                }
            }
            .nobleHallFormStyle()
            .navigationTitle("編輯任務")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("儲存") {
                        Task { await save() }
                    }
                    .disabled(
                        isSaving
                            || (!assignmentFieldsOnly && name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            || name.count > Self.maxNameLength
                            || description.count > Self.maxDescriptionLength
                            || reviewerId.isEmpty
                    )
                }
            }
            .task {
                await loadFormCache()
            }
        }
    }

    private var reviewerOptions: [ProjectMemberDto] {
        members
    }

    private var siteStaffMembers: [ProjectMemberDto] {
        members.filter { $0.memberCategory == "site" }
    }

    private var groupsWithOwner: [ProjectGroupDto] {
        groups.filter { $0.ownerId != nil }
    }

    private func memberLabel(_ member: ProjectMemberDto) -> String {
        member.user.displayName ?? member.user.username ?? member.user.id
    }

    @MainActor
    private func loadFormCache() async {
        if let cached = try? AddTaskFormCache.load(projectCode: projectCode, context: modelContext) {
            categories = cached.categories
            members = cached.members
            groups = cached.groups
            formCacheLoaded = true
            return
        }
        do {
            try await AddTaskFormCache.preload(projectCode: projectCode, spaceId: spaceId, context: modelContext)
            if let cached = try? AddTaskFormCache.load(projectCode: projectCode, context: modelContext) {
                categories = cached.categories
                members = cached.members
                groups = cached.groups
            }
            formCacheLoaded = true
        } catch {
            formCacheLoaded = false
        }
    }

    @MainActor
    private func save() async {
        saveError = nil
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if !assignmentFieldsOnly {
            guard !trimmedName.isEmpty else {
                saveError = "任務名稱不能為空。"
                return
            }
            guard trimmedName.count <= Self.maxNameLength else {
                saveError = "任務名稱最多只能 \(Self.maxNameLength) 個字。"
                return
            }
            guard description.count <= Self.maxDescriptionLength else {
                saveError = "描述最多只能 \(Self.maxDescriptionLength) 個字。"
                return
            }
        }
        guard !reviewerId.isEmpty else {
            saveError = "請選擇審查人員。"
            return
        }
        if executorKind == .user {
            guard !executorUserId.isEmpty else {
                saveError = "請選擇執行人。"
                return
            }
            guard siteStaffMembers.contains(where: { $0.user.id == executorUserId }) else {
                saveError = "執行人須為分類「工地人員」的專案成員。"
                return
            }
        }
        if executorKind == .group {
            guard !executorGroupId.isEmpty else {
                saveError = "請選擇執行群組。"
                return
            }
            guard groupsWithOwner.contains(where: { $0.id == executorGroupId }) else {
                saveError = "執行群組須有負責人，請重新選擇。"
                return
            }
        }
        guard !qualityDrawingId.isEmpty else {
            saveError = "缺少品質圖面資訊，無法更新任務。"
            return
        }

        let includeCoreTaskFields = !assignmentFieldsOnly

        let includeDueDateInPayload: Bool
        let dueISO: String?
        if assignmentFieldsOnly {
            includeDueDateInPayload = false
            dueISO = nil
        } else if includeDueDate {
            includeDueDateInPayload = true
            dueISO = ISO8601DateFormatter().string(from: dueDate)
        } else if initialHadDue {
            includeDueDateInPayload = true
            dueISO = nil
        } else {
            includeDueDateInPayload = false
            dueISO = nil
        }

        let includeCategoryId = !assignmentFieldsOnly && formCacheLoaded && !categories.isEmpty
        let includeReviewerId = formCacheLoaded && !members.isEmpty
        let includeExecutorFields = formCacheLoaded && (!members.isEmpty || !groups.isEmpty)

        if !includeReviewerId {
            saveError = "請連線並載入專案成員列表後，才能變更審查人。"
            return
        }
        if !includeExecutorFields {
            saveError = "請連線並載入專案成員或群組列表後，才能變更執行對象。"
            return
        }

        let effectiveName = assignmentFieldsOnly ? initialTask.name : trimmedName
        let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        let executorPayload: (id: String, type: String?) = {
            switch executorKind {
            case .none:
                return ("", nil)
            case .user:
                return (executorUserId, "user")
            case .group:
                return (executorGroupId, "group")
            }
        }()

        let body = UpdateQualityTaskBody(
            includeCoreTaskFields: includeCoreTaskFields,
            name: effectiveName,
            description: trimmedDescription,
            priority: priority,
            includeDueDateInPayload: includeDueDateInPayload,
            dueDate: dueISO,
            includeCategoryId: includeCategoryId,
            includeReviewerId: includeReviewerId,
            includeExecutorFields: includeExecutorFields,
            categoryId: categoryId,
            reviewerId: reviewerId,
            executorId: executorPayload.id,
            executorType: executorPayload.type
        )

        isSaving = true
        defer { isSaving = false }
        do {
            _ = try await QualityTaskAPI.updateTask(
                projectCode: projectCode,
                qualityDrawingId: qualityDrawingId,
                taskId: taskId,
                body: body,
                spaceId: spaceId
            )
            await onSaved()
        } catch {
            saveError = error.userFacingMessage
        }
    }
}
