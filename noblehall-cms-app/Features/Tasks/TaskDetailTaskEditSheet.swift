import SwiftData
import SwiftUI

/// 任務詳情內第二層 bottom sheet：編輯任務欄位（PATCH quality-tasks）。
struct TaskDetailTaskEditSheet: View {
    let projectCode: String
    let qualityDrawingId: String
    let taskId: String
    let spaceId: String
    let initialTask: QualityTaskDto
    /// 與 Web `basicInfoNonAssignmentFieldsLocked`：建立逾 3 日僅能改審查人等。
    let assignmentFieldsOnly: Bool
    var onCancel: () -> Void
    var onSaved: () async -> Void

    @Environment(\.modelContext) private var modelContext

    @State private var name: String
    @State private var description: String
    @State private var priority: String
    @State private var status: String
    @State private var includeDueDate: Bool
    @State private var dueDate: Date
    @State private var categoryId: String
    @State private var reviewerId: String
    @State private var formCacheLoaded = false
    @State private var categories: [DropdownOptionItemDto] = []
    @State private var members: [ProjectMemberDto] = []
    @State private var saveError: String?
    @State private var isSaving = false

    private let initialHadDue: Bool

    private static let statusChoices: [(value: String, label: String)] = [
        ("pending_assignment", "待指派"),
        ("in_progress", "進行中"),
        ("director_check", "負責人確認"),
        ("in_review", "審查中"),
        ("rejected", "已退回"),
        ("approved", "已完成"),
    ]

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

        let normalizedStatus = Self.normalizeStatus(initialTask.status)
        _status = State(initialValue: normalizedStatus)

        let hadDue = initialTask.dueDate != nil
        initialHadDue = hadDue
        _includeDueDate = State(initialValue: hadDue)
        _dueDate = State(initialValue: initialTask.dueDate ?? Date())

        _categoryId = State(initialValue: initialTask.categoryId ?? "")
        _reviewerId = State(initialValue: initialTask.reviewer?.id ?? "")
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
                            "任務建立已超過三天，僅能修改審查人；執行對象請至網頁工作台調整。其他欄位已鎖定。"
                        )
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }
                }
                Section("任務內容") {
                    TextField("任務名稱", text: $name)
                        .disabled(assignmentFieldsOnly)
                    TextField("說明", text: $description, axis: .vertical)
                        .lineLimit(3 ... 8)
                        .disabled(assignmentFieldsOnly)
                    Picker("優先級", selection: $priority) {
                        Text("低").tag("low")
                        Text("中").tag("medium")
                        Text("高").tag("high")
                    }
                    .disabled(assignmentFieldsOnly)
                    Picker("狀態", selection: $status) {
                        ForEach(Self.statusChoices, id: \.value) { row in
                            Text(row.label).tag(row.value)
                        }
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
                if formCacheLoaded && (!categories.isEmpty || !members.isEmpty) {
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
                        if !members.isEmpty {
                            Picker("審查人", selection: $reviewerId) {
                                Text("（不選）").tag("")
                                ForEach(members) { m in
                                    Text(m.user.displayName ?? m.user.username ?? m.user.id)
                                        .tag(m.user.id)
                                }
                            }
                        }
                    }
                } else if formCacheLoaded {
                    Section {
                        Text(
                            assignmentFieldsOnly
                                ? "快取中尚無專案成員，無法變更審查人。請稍後再試或至網頁工作台處理。"
                                : "快取中尚無可選的類別或專案成員，無法在此變更審查人或類別。"
                        )
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }
                } else {
                    Section {
                        Text(
                            assignmentFieldsOnly
                                ? "未載入成員／類別快取：目前無法變更審查人。請連線後建立任務或稍後再試以載入成員列表。"
                                : "未載入成員／類別快取：僅可編輯名稱、說明、優先級、狀態與到期日。建立任務或稍後再試可載入完整選項。"
                        )
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }
                }
            }
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
                    )
                }
            }
            .task {
                await loadFormCache()
            }
        }
    }

    private static func normalizeStatus(_ raw: String?) -> String {
        let normalized = (raw ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "-", with: "_")
        let allowed = Set(statusChoices.map(\.value))
        if allowed.contains(normalized) { return normalized }
        return "pending_assignment"
    }

    @MainActor
    private func loadFormCache() async {
        if let cached = try? AddTaskFormCache.load(projectCode: projectCode, context: modelContext) {
            categories = cached.categories
            members = cached.members
            formCacheLoaded = true
            return
        }
        do {
            try await AddTaskFormCache.preload(projectCode: projectCode, spaceId: spaceId, context: modelContext)
            if let cached = try? AddTaskFormCache.load(projectCode: projectCode, context: modelContext) {
                categories = cached.categories
                members = cached.members
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

        if assignmentFieldsOnly, !includeReviewerId {
            saveError = "請連線並載入專案成員列表後，才能變更審查人。"
            return
        }

        let effectiveName = assignmentFieldsOnly ? initialTask.name : trimmedName

        let body = UpdateQualityTaskBody(
            includeCoreTaskFields: includeCoreTaskFields,
            name: effectiveName,
            description: description,
            priority: priority,
            status: status,
            includeDueDateInPayload: includeDueDateInPayload,
            dueDate: dueISO,
            includeCategoryId: includeCategoryId,
            includeReviewerId: includeReviewerId,
            categoryId: categoryId,
            reviewerId: reviewerId
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
            saveError = error.localizedDescription
        }
    }
}
