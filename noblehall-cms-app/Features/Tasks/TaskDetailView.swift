import PhotosUI
import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// 與後端 `QUALITY_TASK_HOUSEHOLD_POINT_ID_PREFIX` 一致：`repository` 群組點位 `id` 為此前綴 + `group.uuid`。
private let qualityTaskHouseholdPointIdPrefix = "qt-hh:"

/// 與後端及「新增執行紀錄」相同：單筆執行最多附件數。
private let maxExecutionAttachmentsPerEntry = 3

/// 任務在平面圖上的空間錨點（多為 Web PlanViewer／pdf.js 畫布像素；亦可能為 0…1 正規化）。
private struct TaskSpaceMarker: Equatable {
    let x: Double
    let y: Double
    let title: String
    let taskCount: Int
    let incompleteTaskCount: Int
}

struct TaskDetailView: View {
    let projectCode: String
    let taskId: String
    /// 列表帶入的圖面 id（詳情 API 缺欄位或離線僅有列表快取時仍可載入平面圖）。
    var qualityDrawingIdHint: String? = nil
    let onClose: () -> Void
    var onTaskChanged: (() async -> Void)? = nil

    @Environment(SessionStore.self) private var session
    @Environment(NetworkPathMonitor.self) private var network
    @Environment(\.modelContext) private var modelContext

    @State private var detail: QualityTaskDetailResponseDto?
    @State private var resolvedDrawingId: String?
    @State private var floorImageURL: URL?
    @State private var floorImageFallbackURL: URL?
    @State private var offlineFloorImage: UIImage?
    @State private var offlineMarkerReferenceSize: CGSize = .zero
    @State private var roomPoints: [QualityTaskRoomPointDto] = []
    @State private var spaceMarker: TaskSpaceMarker?
    @State private var loadError: String?
    @State private var floorPlanError: String?
    @State private var showMainSheet = true
    @State private var showTaskEditSheet = false
    @State private var bottomTab: BottomTab = .task
    @State private var showAddExecution = false
    /// 新增執行紀錄 sheet 預設展開至大高度（仍可拖回中間）。
    @State private var addExecutionSheetDetent: PresentationDetent = .large
    @State private var isLoading = true
    @State private var pendingExecutions: [PendingExecutionOutbox] = []
    @State private var executionSaveNotice: String?
    @State private var executionSaveNoticeID: UUID?
    @State private var editingLedgerExecution: TaskLedgerEntryDto?
    @State private var executionEditDraftText = ""
    @State private var executionEditPickedPhotos: [PickedUploadPhoto] = []
    @State private var executionEditError: String?
    @State private var viewingLedgerEntry: TaskLedgerEntryDto?
    @State private var isSavingExecutionEdit = false
    @State private var showDeleteExecutionConfirm = false
    @State private var pendingDeleteLedgerEntry: TaskLedgerEntryDto?
    @State private var reviewDraft: ReviewActionDraft?
    @State private var reviewCommentText = ""
    @State private var reviewPickedPhotos: [PickedUploadPhoto] = []
    @State private var reviewSubmitError: String?
    @State private var isSubmittingReview = false
    @State private var showCompleteSubmitConfirm = false
    @State private var isSubmittingExecution = false

    enum BottomTab: String, CaseIterable, Identifiable {
        case task = "任務資料"
        case records = "執行紀錄"
        var id: String { rawValue }
    }

    private enum ReviewKind: String, Identifiable {
        case director
        case reviewer

        var id: String { rawValue }

        var commentLabel: String {
            switch self {
            case .director: return "負責人意見"
            case .reviewer: return "審核意見"
            }
        }

        var approvedTitle: String {
            switch self {
            case .director: return "負責人通過"
            case .reviewer: return "審查通過"
            }
        }

        var rejectedTitle: String {
            switch self {
            case .director: return "退回重做"
            case .reviewer: return "退回審核"
            }
        }
    }

    private struct ReviewActionDraft: Identifiable {
        let kind: ReviewKind
        let result: QualityTaskReviewResult

        var id: String { "\(kind.rawValue)-\(result.rawValue)" }

        var title: String {
            result == .approved ? kind.approvedTitle : kind.rejectedTitle
        }
    }

    private struct ReviewActionSheet: View {
        let draft: ReviewActionDraft
        @Binding var comment: String
        @Binding var photos: [PickedUploadPhoto]
        let errorMessage: String?
        let isSubmitting: Bool
        let onCancel: () -> Void
        let onSubmit: () -> Void

        var body: some View {
            NavigationStack {
                Form {
                    Section {
                        TextField("\(draft.kind.commentLabel)（選填）", text: $comment, axis: .vertical)
                            .lineLimit(4 ... 12)
                        Text("\(comment.count)/2000")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(comment.count > 2000 ? .red : .secondary)
                    } header: {
                        Text(draft.kind.commentLabel)
                    } footer: {
                        Text(draft.result == .approved ? "通過後會進入下一階段或完成任務。" : "退回後任務會回到執行人待處理。")
                    }

                    Section {
                        TaskAttachmentPhotoPickerSection(
                            photos: $photos,
                            maxCount: maxExecutionAttachmentsPerEntry,
                            filenamePrefix: draft.kind == .director ? "director-review" : "review",
                            isDisabled: isSubmitting,
                            caption: "可補充現場照片或截圖，最多 \(maxExecutionAttachmentsPerEntry) 張。",
                            onError: { _ in }
                        )
                    } header: {
                        Text("附件")
                    }

                    if let errorMessage, !errorMessage.isEmpty {
                        Section {
                            Text(errorMessage)
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                    }
                }
                .nobleHallFormStyle()
                .navigationTitle(draft.title)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消", action: onCancel)
                            .disabled(isSubmitting)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button {
                            onSubmit()
                        } label: {
                            if isSubmitting {
                                ProgressView()
                            } else {
                                Text(draft.result == .approved ? "通過" : "退回")
                            }
                        }
                        .disabled(isSubmitting || comment.count > 2000)
                    }
                }
            }
        }
    }

    private struct LedgerEntryDetailSheet: View {
        let entry: TaskLedgerEntryDto
        let spaceId: String?
        let onClose: () -> Void

        var body: some View {
            NavigationStack {
                List {
                    Section("紀錄") {
                        LabeledContent("類型", value: TaskLedgerPresentation.kindLabel(entry.kind))
                        if let round = entry.round {
                            LabeledContent("輪次", value: "第 \(round) 輪")
                        }
                        LabeledContent("人員", value: entry.actor.displayName ?? entry.actor.username ?? entry.actor.id)
                        LabeledContent("時間", value: AppDateTimeFormat.fullDateTime(entry.occurredAt))
                        if let result = entry.result, !result.isEmpty {
                            LabeledContent("結果", value: reviewResultLabel(result))
                        }
                    }

                    if let body = entry.body, !body.isEmpty {
                        Section("內容") {
                            Text(body)
                                .font(.body)
                                .textSelection(.enabled)
                        }
                    }

                    if let attachments = entry.attachments, !attachments.isEmpty {
                        Section("附件") {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 10) {
                                    ForEach(attachments) { attachment in
                                        ExecutionAttachmentThumbnail(attachment: attachment, spaceId: spaceId)
                                    }
                                }
                                .padding(.vertical, 4)
                            }
                            .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 0))
                        }
                    }
                }
                .nobleHallGroupedListStyle()
                .navigationTitle("查看紀錄")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完成", action: onClose)
                    }
                }
            }
        }

        private func reviewResultLabel(_ raw: String) -> String {
            switch raw.lowercased() {
            case "approved":
                return "通過"
            case "rejected":
                return "退回"
            default:
                return QualityTaskStatusLabels.displayName(for: raw)
            }
        }
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                FloorPlanCanvasView(
                    projectCode: projectCode,
                    qualityDrawingId: resolvedDrawingId,
                    imageURL: floorImageURL,
                    fallbackImageURL: floorImageFallbackURL,
                    offlineImage: offlineFloorImage,
                    offlineMarkerReferenceSize: offlineMarkerReferenceSize,
                    spaceId: session.spaceId,
                    marker: spaceMarker,
                    loadError: $floorPlanError
                )
                    .ignoresSafeArea()

                // 錯誤提示須放在**上方**：`.sheet` 半屏會蓋住螢幕下半部，先前放在底部等於被白底遮住。
                VStack(spacing: 0) {
                    if let planTitle = resolvedQualityDrawingTitle {
                        Text(planTitle)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial)
                            .accessibilityAddTraits(.isHeader)
                            .accessibilityLabel("平面圖 \(planTitle)")
                    }
                    HStack(alignment: .top, spacing: 8) {
                        Group {
                            if (floorPlanError?.isEmpty == false) || (loadError?.isEmpty == false) {
                                VStack(alignment: .leading, spacing: 6) {
                                    if let fp = floorPlanError, !fp.isEmpty {
                                        Text(fp)
                                            .font(.caption2)
                                            .multilineTextAlignment(.leading)
                                            .foregroundStyle(.primary)
                                    }
                                    if let le = loadError, !le.isEmpty {
                                        Text(le)
                                            .font(.caption2)
                                            .multilineTextAlignment(.leading)
                                            .foregroundStyle(.primary)
                                    }
                                }
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                            } else {
                                Spacer(minLength: 0)
                            }
                        }
                        Spacer(minLength: 8)
                        if !showMainSheet {
                            Button {
                                showMainSheet = true
                            } label: {
                                Image(systemName: "doc.text.fill")
                                    .symbolRenderingMode(.hierarchical)
                                    .font(.title2)
                                    .padding(4)
                            }
                            .accessibilityLabel("任務資料")
                            .accessibilityHint("開啟任務資料與執行紀錄")
                        }
                        Button(action: onClose) {
                            Image(systemName: "xmark.circle.fill")
                                .symbolRenderingMode(.hierarchical)
                                .font(.title2)
                                .padding(4)
                        }
                        .accessibilityLabel("關閉")
                    }
                    .padding(.horizontal, 10)
                    .padding(.top, 6)
                    Spacer()
                }
            }
            .navigationBarHidden(true)
            .toolbar(.hidden, for: .navigationBar)
            .sheet(isPresented: $showMainSheet) {
                mainBottomSheet
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .overlay {
                if isLoading, detail == nil { ProgressView("載入中…").padding().background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12)) }
            }
            .onChange(of: showMainSheet) { _, visible in
                if !visible {
                    showAddExecution = false
                    showTaskEditSheet = false
                }
            }
            .task {
                await loadAll()
                refreshPendingExecutions()
            }
            .onChange(of: network.isConnected) { _, online in
                guard online, let sid = session.spaceId else { return }
                Task {
                    await OutboxSync.flushPending(modelContext: modelContext, spaceId: sid, isOnline: true)
                    refreshPendingExecutions()
                    await loadAll()
                }
            }
        }
        .dismissKeyboardOnTapOutside()
    }

    private func refreshPendingExecutions() {
        pendingExecutions = (try? ExecutionOutbox.pendingForTask(
            projectCode: projectCode,
            taskId: taskId,
            context: modelContext
        )) ?? []
    }

    private var mainBottomSheet: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("", selection: $bottomTab) {
                    ForEach(BottomTab.allCases) { t in
                        Text(t.rawValue).tag(t)
                    }
                }
                .pickerStyle(.segmented)
                .padding()

                if bottomTab == .task {
                    if let r = taskEditBlockedReason {
                        Text(r)
                            .font(.caption2)
                            .foregroundStyle(.orange)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 12)
                            .padding(.bottom, 6)
                    } else if let hint = taskEditLimitedToAssignmentHint {
                        Text(hint)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 12)
                            .padding(.bottom, 6)
                    }
                }

                Group {
                    switch bottomTab {
                    case .task:
                        taskMetaScroll
                    case .records:
                        executionList
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            .nobleHallScreen()
            .navigationTitle("任務")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("編輯") {
                        showTaskEditSheet = true
                    }
                    .disabled(detail?.task == nil || taskEditBlockedReason != nil)
                }
            }
        }
        // 從「任務資料」sheet 內再 present，才可與主 sheet 疊加；勿與外層 `showMainSheet` 並列兩個 `.sheet`。
        .sheet(isPresented: $showAddExecution) {
            AddExecutionSheet(
                onCancel: { showAddExecution = false },
                onSave: { text, attachments in
                    let ok = await saveNewExecution(reply: text, attachments: attachments)
                    if ok { showAddExecution = false }
                    return ok
                }
            )
            .presentationDetents([.medium, .large], selection: $addExecutionSheetDetent)
            .presentationDragIndicator(.visible)
            .onAppear { addExecutionSheetDetent = .large }
        }
        .sheet(isPresented: $showTaskEditSheet) {
            Group {
                if let t = detail?.task, let sid = session.spaceId,
                   let qdid = resolvedQualityDrawingId(for: t), !qdid.isEmpty
                {
                    TaskDetailTaskEditSheet(
                        projectCode: projectCode,
                        qualityDrawingId: qdid,
                        taskId: taskId,
                        spaceId: sid,
                        initialTask: t,
                        assignmentFieldsOnly: QualityTaskEditEligibility.assignmentFieldsOnly(
                            task: t,
                            userId: session.currentUser?.id,
                            hasAssignPermission: canAssignQualityTask
                        ),
                        onCancel: { showTaskEditSheet = false },
                        onSaved: {
                            showTaskEditSheet = false
                            await loadAll()
                            await notifyTaskChanged()
                        }
                    )
                } else {
                    NavigationStack {
                        ContentUnavailableView("無法編輯", systemImage: "exclamationmark.triangle")
                            .toolbar {
                                ToolbarItem(placement: .cancellationAction) {
                                    Button("關閉") { showTaskEditSheet = false }
                                }
                            }
                    }
                }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $reviewDraft) { draft in
            ReviewActionSheet(
                draft: draft,
                comment: $reviewCommentText,
                photos: $reviewPickedPhotos,
                errorMessage: reviewSubmitError,
                isSubmitting: isSubmittingReview,
                onCancel: {
                    guard !isSubmittingReview else { return }
                    clearReviewDraft()
                },
                onSubmit: {
                    Task { await submitReviewAction(draft: draft) }
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
            .onAppear {
                reviewCommentText = ""
                reviewPickedPhotos = []
                reviewSubmitError = nil
            }
        }
    }

    private var taskMetaScroll: some View {
        ScrollView {
            if let t = detail?.task {
                taskInfoSections(task: t)
                    .padding()
            } else if let row = cachedListRow {
                VStack(alignment: .leading, spacing: 12) {
                    LabeledContent("名稱", value: row.title)
                    if let st = row.status {
                        LabeledContent("狀態", value: QualityTaskStatusLabels.displayName(for: st))
                    }
                    if let drawing = row.drawingName, !drawing.isEmpty {
                        LabeledContent("平面圖", value: drawing)
                    }
                    if !network.isConnected {
                        Text("離線：顯示列表快取資料，連線後可載入完整任務內容。")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
            } else {
                ContentUnavailableView("無資料", systemImage: "doc")
            }
        }
        .dismissKeyboardOnScroll()
    }

    @ViewBuilder
    private func taskInfoSections(task t: QualityTaskDto) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            LabeledContent("名稱", value: t.name)
            if let st = t.status {
                LabeledContent("狀態", value: QualityTaskStatusLabels.displayName(for: st))
            }
            if let drawing = t.qualityDrawing?.name, !drawing.isEmpty {
                LabeledContent("平面圖", value: drawing)
            }
            if let pr = t.priority, !pr.isEmpty { LabeledContent("優先級", value: pr) }
            if let cat = t.category?.value, !cat.isEmpty { LabeledContent("類別", value: cat) }
            if let g = t.group?.name, !g.isEmpty { LabeledContent("群組", value: g) }
            if let room = t.room?.name, !room.isEmpty { LabeledContent("空間", value: room) }
            LabeledContent("執行對象", value: Self.executorLabel(for: t))
            if let reviewer = t.reviewer?.displayName ?? t.reviewer?.username, !reviewer.isEmpty {
                LabeledContent("審查人", value: reviewer)
            }
            if let due = t.dueDate {
                LabeledContent("到期日", value: AppDateTimeFormat.yearMonthDay(due))
            }
            if let created = t.createdAt {
                LabeledContent("建立時間", value: AppDateTimeFormat.fullDateTime(created))
            }
            if let desc = t.description, !desc.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("說明").font(.subheadline).foregroundStyle(.secondary)
                    Text(desc).font(.body)
                }
            }
        }
    }

    private var cachedListRow: CachedTaskRow? {
        let rows = (try? LocalTaskCache.tasks(projectCode: projectCode, context: modelContext)) ?? []
        return rows.first { $0.taskId == taskId }
    }

    /// 頂部標題：優先詳情 API，否則列表快取之圖面名稱。
    private var resolvedQualityDrawingTitle: String? {
        if let s = detail?.task.qualityDrawing?.name.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
            return s
        }
        if let s = cachedListRow?.drawingName?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty {
            return s
        }
        return nil
    }

    /// 後端 PATCH 任務須帶品質圖面 id（巢狀路由）。
    private var hasQualityDrawingForEdit: Bool {
        if let id = resolvedQualityDrawingId(for: detail?.task), !id.isEmpty { return true }
        return false
    }

    /// 無法開啟「編輯」時的原因（與 Web 任務管理一致）。
    private var taskEditBlockedReason: String? {
        guard let t = detail?.task else { return "尚未載入任務資料。" }
        return QualityTaskEditEligibility.taskEditSheetBlockedReason(
            task: t,
            userId: session.currentUser?.id,
            isOnline: network.isConnected,
            hasQualityDrawing: hasQualityDrawingForEdit,
            hasAssignPermission: canAssignQualityTask,
            hasUpdatePermission: canUpdateQualityTask
        )
    }

    /// 可編輯但僅限審查人時的補充說明。
    private var taskEditLimitedToAssignmentHint: String? {
        guard let t = detail?.task else { return nil }
        guard taskEditBlockedReason == nil else { return nil }
        let assignmentOnly = QualityTaskEditEligibility.assignmentFieldsOnly(
            task: t,
            userId: session.currentUser?.id,
            hasAssignPermission: canAssignQualityTask
        )
        guard assignmentOnly else { return nil }
        return "此任務目前僅能修改審查人與執行對象。"
    }

    private var canAssignQualityTask: Bool {
        detail?.viewer?.canAssignQualityTask ?? hasQualityTaskManagementPermission("assign")
    }

    private var canUpdateQualityTask: Bool {
        detail?.viewer?.canUpdateQualityTask ?? hasQualityTaskManagementPermission("update")
    }

    private func hasQualityTaskManagementPermission(_ action: String) -> Bool {
        guard let permissions = session.currentUser?.permissions else { return false }
        return permissions.contains { raw in
            let parts = raw.lowercased().split(separator: ":").map(String.init)
            guard parts.count >= 2 else { return false }
            return (parts[0] == "quality_task_management" || parts[0] == "quality_task")
                && parts[1] == action
        }
    }

    private static func executorLabel(for task: QualityTaskDto) -> String {
        let name = task.executor?.displayName ?? task.executor?.name ?? task.executor?.username
        switch task.executorType?.lowercased() {
        case "group":
            return name.map { "群組 · \($0)" } ?? (task.group?.name ?? "群組")
        case "user":
            return name.map { "個人 · \($0)" } ?? "個人"
        default:
            return name ?? "—"
        }
    }

    private var executionList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 14) {
                if !network.isConnected {
                    executionNoticeCard(
                        title: "離線模式",
                        message: "執行紀錄將暫存，連線後自動上傳。",
                        systemImage: "icloud.and.arrow.up",
                        tint: .secondary
                    )
                }
                if let notice = executionSaveNotice, !notice.isEmpty {
                    executionNoticeCard(
                        title: "已儲存",
                        message: notice,
                        systemImage: "checkmark.circle.fill",
                        tint: .green
                    )
                }
                ForEach(pendingExecutions, id: \.localId) { pending in
                    pendingExecutionCard(pending: pending)
                }
                if let ledger = detail?.ledger, !ledger.isEmpty, let task = detail?.task {
                    ForEach(Array(ledger.reversed())) { entry in
                        ledgerEntryCard(entry: entry, task: task)
                    }
                } else if let task = detail?.task, let items = detail?.latestSubmission?.executions, !items.isEmpty {
                    ForEach(Array(items.reversed())) { ex in
                        fallbackExecutionCard(ex: ex, task: task)
                    }
                }
                executionStageActionArea
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .sheet(item: $editingLedgerExecution) { entry in
            NavigationStack {
                Form {
                    Section {
                        TextField("執行說明", text: $executionEditDraftText, axis: .vertical)
                            .lineLimit(4 ... 14)
                    }
                    Section {
                        if let list = entry.attachments, !list.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(list) { att in
                                        ExecutionAttachmentThumbnail(attachment: att, spaceId: session.spaceId)
                                    }
                                }
                            }
                            .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 8, trailing: 0))
                        }
                        if network.isConnected, maxAdditionalExecutionPhotos(for: entry) > 0 {
                            TaskAttachmentPhotoPickerSection(
                                photos: $executionEditPickedPhotos,
                                maxCount: maxAdditionalExecutionPhotos(for: entry),
                                filenamePrefix: "execution",
                                isDisabled: isSavingExecutionEdit,
                                caption: "與新增紀錄相同：含既有附件每筆最多 \(maxExecutionAttachmentsPerEntry) 個。",
                                onError: { executionEditError = $0 }
                            )
                        } else if !network.isConnected {
                            Text("連線後才能上傳附件。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        } else if maxAdditionalExecutionPhotos(for: entry) == 0 {
                            Text("已達每筆 \(maxExecutionAttachmentsPerEntry) 個附件上限。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } header: {
                        Text("附件")
                    }
                    if let executionEditError, !executionEditError.isEmpty {
                        Section {
                            Text(executionEditError)
                                .font(.footnote)
                                .foregroundStyle(.red)
                        }
                    }
                }
                .nobleHallFormStyle()
                .navigationTitle("編輯執行紀錄")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") {
                            executionEditPickedPhotos = []
                            editingLedgerExecution = nil
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("儲存") {
                            Task { await saveLedgerExecutionEdit(entry: entry) }
                        }
                        .disabled(isSavingExecutionEdit || !ledgerExecutionEditHasChanges(entry: entry))
                    }
                }
                .onAppear {
                    executionEditDraftText = entry.body ?? ""
                    executionEditPickedPhotos = []
                    executionEditError = nil
                }
            }
            .presentationDetents([.medium, .large])
        }
        .fullScreenCover(item: $viewingLedgerEntry) { entry in
            LedgerEntryDetailSheet(
                entry: entry,
                spaceId: session.spaceId,
                onClose: { viewingLedgerEntry = nil }
            )
        }
        .confirmationDialog("刪除此筆執行紀錄？", isPresented: $showDeleteExecutionConfirm, titleVisibility: .visible) {
            Button("刪除", role: .destructive) {
                let entry = pendingDeleteLedgerEntry
                pendingDeleteLedgerEntry = nil
                if let entry {
                    Task { await deleteLedgerExecution(entry: entry) }
                }
            }
            Button("取消", role: .cancel) {
                pendingDeleteLedgerEntry = nil
            }
        } message: {
            Text("此動作無法復原。僅未送出、任務進行中、日曆三天內且由您建立的執行紀錄可刪除。")
        }
        .confirmationDialog("完成提交？", isPresented: $showCompleteSubmitConfirm, titleVisibility: .visible) {
            Button("送出") {
                Task { await submitCurrentExecutionsForReview() }
            }
            .disabled(isSubmittingExecution)
            Button("取消", role: .cancel) {}
        } message: {
            Text(completeSubmitConfirmMessage)
        }
    }

    @ViewBuilder
    private var executionStageActionArea: some View {
        if let kind = availableReviewKind {
            reviewActionButtons(kind: kind)
        } else if isTaskInReviewStage {
            executionNoticeCard(
                title: "已進入審核階段",
                message: reviewStageReadOnlyMessage,
                systemImage: "lock.fill",
                tint: .secondary
            )
        } else if canCreateExecutionForCurrentTask {
            addExecutionCardButton
            if showCompleteSubmitEntry {
                completeSubmitButton
            }
        }
    }

    private var isTaskInReviewStage: Bool {
        guard let task = detail?.task else { return false }
        let status = QualityTaskEditEligibility.normalizedStatus(task.status)
        return status == "director_check" || status == "in_review"
    }

    private var canCreateExecutionForCurrentTask: Bool {
        guard let task = detail?.task else { return false }
        let status = QualityTaskEditEligibility.normalizedStatus(task.status)
        return status == "in_progress" || status == "rejected"
    }

    private var currentRoundExecutionCount: Int {
        if let list = detail?.latestSubmission?.executions {
            return list.count
        }
        if let ledger = detail?.ledger {
            return ledger.filter { $0.kind == .execution && $0.submissionId == nil }.count
        }
        return 0
    }

    private var isCurrentUserTaskExecutor: Bool {
        guard let task = detail?.task,
              QualityTaskEditEligibility.normalizedStatus(task.status) == "in_progress",
              task.executorType?.lowercased() == "user",
              let uid = session.currentUser?.id,
              !uid.isEmpty
        else {
            return false
        }
        return task.executor?.id == uid || task.executorId == uid
    }

    private var showCompleteSubmitEntry: Bool {
        guard network.isConnected,
              isCurrentUserTaskExecutor,
              currentRoundExecutionCount > 0,
              let task = detail?.task,
              let qdid = resolvedQualityDrawingId(for: task),
              !qdid.isEmpty
        else {
            return false
        }
        return true
    }

    private var completeSubmitConfirmMessage: String {
        let count = currentRoundExecutionCount
        let recordText = count > 0 ? "將送出 \(count) 筆已保存的執行紀錄。" : "尚無可送出的執行紀錄。"
        return "確定要完成提交嗎？\n\n\(recordText)\n送出後將進入審核階段，無法再新增執行紀錄。"
    }

    private var reviewStageReadOnlyMessage: String {
        guard network.isConnected else { return "離線時無法審核；此階段也不能新增執行紀錄。" }
        guard detail?.latestSubmission?.id?.isEmpty == false else {
            return "尚未取得提交資料，無法審核；此階段也不能新增執行紀錄。"
        }
        return "此階段不能新增執行紀錄。若您是審核人或專案負責人，請確認帳號權限後操作。"
    }

    private var availableReviewKind: ReviewKind? {
        guard network.isConnected,
              let task = detail?.task,
              let submissionId = detail?.latestSubmission?.id,
              !submissionId.isEmpty,
              let qdid = resolvedQualityDrawingId(for: task),
              !qdid.isEmpty
        else {
            return nil
        }

        let status = QualityTaskEditEligibility.normalizedStatus(task.status)
        let currentUserId = session.currentUser?.id
        if status == "director_check", detail?.viewer?.isProjectOwner == true {
            return .director
        }
        if status == "in_review",
           let currentUserId,
           !currentUserId.isEmpty,
           task.reviewer?.id == currentUserId
        {
            return .reviewer
        }
        return nil
    }

    private func reviewActionButtons(kind: ReviewKind) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("此任務已進入\(kind == .director ? "負責人確認" : "審核")階段，不能再新增執行紀錄。")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Spacer()

                Button {
                    openReviewDraft(kind: kind, result: .rejected)
                } label: {
                    Label("退回", systemImage: "arrow.uturn.backward.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.bordered)
                .controlSize(.regular)
                .tint(.red)

                Button {
                    openReviewDraft(kind: kind, result: .approved)
                } label: {
                    Label("通過", systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)

                Spacer()
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color(.separator).opacity(0.35), lineWidth: 0.5)
        )
    }

    private var completeSubmitButton: some View {
        Button {
            showCompleteSubmitConfirm = true
        } label: {
            HStack(spacing: 10) {
                if isSubmittingExecution {
                    ProgressView()
                } else {
                    Image(systemName: "paperplane.circle.fill")
                        .font(.title2)
                        .foregroundStyle(NobleHallTheme.brandGold)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text("完成提交")
                        .font(.headline)
                        .foregroundStyle(NobleHallTheme.ink)
                    Text("送出 \(currentRoundExecutionCount) 筆執行紀錄進入審核")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(NobleHallTheme.brandGold.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(NobleHallTheme.brandGold.opacity(0.30), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isSubmittingExecution)
    }

    private var addExecutionCardButton: some View {
        Button {
            executionSaveNotice = nil
            executionSaveNoticeID = nil
            showAddExecution = true
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "plus.circle.fill")
                    .font(.title2)
                    .foregroundStyle(NobleHallTheme.brandGold)
                Text("新增執行紀錄")
                    .font(.headline)
                    .foregroundStyle(NobleHallTheme.ink)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(NobleHallTheme.brandGold.opacity(0.12))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(NobleHallTheme.brandGold.opacity(0.30), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func executionNoticeCard(title: String, message: String, systemImage: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.subheadline.weight(.semibold))
                Text(message).font(.footnote).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color(.separator).opacity(0.35), lineWidth: 0.5)
        )
    }

    private func showExecutionSaveNotice(_ message: String) {
        let id = UUID()
        executionSaveNotice = message
        executionSaveNoticeID = id
        Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            await MainActor.run {
                guard executionSaveNoticeID == id else { return }
                executionSaveNotice = nil
                executionSaveNoticeID = nil
            }
        }
    }

    private func pendingExecutionCard(pending: PendingExecutionOutbox) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(session.currentUser?.displayName ?? "我")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Text("待上傳")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.18), in: Capsule())
                    .foregroundStyle(.orange)
            }
            if !pending.executionReply.isEmpty {
                Text(pending.executionReply).font(.body)
            }
            let photoCount = ExecutionOutbox.photoCount(for: pending)
            if photoCount > 0 {
                Label("\(photoCount) 張照片（待上傳）", systemImage: "photo")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(AppDateTimeFormat.fullDateTime(pending.enqueuedAt))
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color(.separator).opacity(0.35), lineWidth: 0.5)
        )
    }

    private func ledgerEntryCard(entry: TaskLedgerEntryDto, task: QualityTaskDto) -> some View {
        let canEdit = network.isConnected
            && TaskLedgerPresentation.canModifyDraftExecution(
                entry: entry,
                task: task,
                currentUserId: session.currentUser?.id
            )
        let hint = TaskLedgerPresentation.draftExecutionEditBlockedReason(
            entry: entry,
            task: task,
            currentUserId: session.currentUser?.id,
            isOnline: network.isConnected
        )

        return Group {
            if canEdit {
                Button {
                    executionEditDraftText = entry.body ?? ""
                    executionEditError = nil
                    editingLedgerExecution = entry
                } label: {
                    ledgerEntryCardBody(entry: entry, footnote: nil, showChevron: true)
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    viewingLedgerEntry = entry
                } label: {
                    ledgerEntryCardBody(
                        entry: entry,
                        footnote: entry.kind == .execution ? hint : nil,
                        showChevron: true
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .contextMenu {
            if network.isConnected,
               TaskLedgerPresentation.canModifyDraftExecution(
                   entry: entry,
                   task: task,
                   currentUserId: session.currentUser?.id
               )
            {
                Button("編輯說明") {
                    executionEditDraftText = entry.body ?? ""
                    executionEditError = nil
                    editingLedgerExecution = entry
                }
                Button("刪除", role: .destructive) {
                    pendingDeleteLedgerEntry = entry
                    showDeleteExecutionConfirm = true
                }
            }
        }
    }

    private func ledgerEntryCardBody(entry: TaskLedgerEntryDto, footnote: String?, showChevron: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(TaskLedgerPresentation.kindLabel(entry.kind))
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(.systemGray5), in: Capsule())
                    if let r = entry.round {
                        Text("第 \(r) 輪")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    Spacer(minLength: 0)
                    Text(AppDateTimeFormat.fullDateTime(entry.occurredAt))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Text(entry.actor.displayName ?? entry.actor.username ?? entry.actor.id)
                    .font(.subheadline.weight(.semibold))
                if let body = entry.body, !body.isEmpty {
                    Text(body).font(.body)
                }
                if let r = entry.result, !r.isEmpty {
                    Text(QualityTaskStatusLabels.displayName(for: r))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                let attCount = entry.attachments?.count ?? 0
                if attCount > 0 {
                    Label("\(attCount) 個附件", systemImage: "paperclip")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let footnote, !footnote.isEmpty {
                    Text(footnote)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if showChevron {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color(.separator).opacity(0.35), lineWidth: 0.5)
        )
    }

    private func fallbackExecutionCard(ex: ExecutionRecordDto, task: QualityTaskDto) -> some View {
        let canEdit = network.isConnected
            && TaskLedgerPresentation.canModifyFallbackExecution(ex: ex, task: task, currentUserId: session.currentUser?.id)
        let hint = TaskLedgerPresentation.fallbackExecutionEditBlockedReason(
            ex: ex,
            task: task,
            currentUserId: session.currentUser?.id,
            isOnline: network.isConnected
        )
        let synthetic = TaskLedgerPresentation.ledgerEntryFromFallbackExecution(ex)

        return Group {
            if canEdit {
                Button {
                    executionEditDraftText = synthetic.body ?? ""
                    executionEditError = nil
                    editingLedgerExecution = synthetic
                } label: {
                    fallbackExecutionCardBody(ex: ex, footnote: nil, showChevron: true)
                }
                .buttonStyle(.plain)
            } else {
                Button {
                    viewingLedgerEntry = synthetic
                } label: {
                    fallbackExecutionCardBody(ex: ex, footnote: hint, showChevron: true)
                }
                .buttonStyle(.plain)
            }
        }
        .contextMenu {
            if network.isConnected,
               TaskLedgerPresentation.canModifyFallbackExecution(ex: ex, task: task, currentUserId: session.currentUser?.id)
            {
                Button("編輯說明") {
                    executionEditDraftText = synthetic.body ?? ""
                    executionEditError = nil
                    editingLedgerExecution = synthetic
                }
                Button("刪除", role: .destructive) {
                    pendingDeleteLedgerEntry = synthetic
                    showDeleteExecutionConfirm = true
                }
            }
        }
    }

    private func fallbackExecutionCardBody(ex: ExecutionRecordDto, footnote: String?, showChevron: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("執行")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color(.systemGray5), in: Capsule())
                    Spacer(minLength: 0)
                    if let d = ex.executedAt ?? ex.createdAt {
                        Text(AppDateTimeFormat.fullDateTime(d))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                Text(ex.executor?.displayName ?? ex.executor?.username ?? "—")
                    .font(.subheadline.weight(.semibold))
                if let r = ex.executionReply, !r.isEmpty { Text(r).font(.body) }
                let attCount = ex.attachments?.count ?? 0
                if attCount > 0 {
                    Label("\(attCount) 個附件", systemImage: "paperclip")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let footnote, !footnote.isEmpty {
                    Text(footnote)
                        .font(.caption2)
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if showChevron {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color(.separator).opacity(0.35), lineWidth: 0.5)
        )
    }

    private func maxAdditionalExecutionPhotos(for entry: TaskLedgerEntryDto) -> Int {
        max(0, maxExecutionAttachmentsPerEntry - (entry.attachments?.count ?? 0))
    }

    private func ledgerExecutionEditHasChanges(entry: TaskLedgerEntryDto) -> Bool {
        let original = (entry.body ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmed = executionEditDraftText.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed != original || !executionEditPickedPhotos.isEmpty
    }

    private func saveLedgerExecutionEdit(entry: TaskLedgerEntryDto) async {
        guard let sid = session.spaceId else {
            executionEditError = "缺少 Space。"
            return
        }
        guard let qdid = resolvedQualityDrawingId(for: detail?.task), !qdid.isEmpty else {
            executionEditError = "缺少平面圖資訊。"
            return
        }
        isSavingExecutionEdit = true
        executionEditError = nil
        defer { isSavingExecutionEdit = false }
        let trimmed = executionEditDraftText.trimmingCharacters(in: .whitespacesAndNewlines)
        let original = (entry.body ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let textChanged = trimmed != original
        let maxNew = maxAdditionalExecutionPhotos(for: entry)
        do {
            if textChanged {
                try await QualityTaskAPI.updateExecution(
                    projectCode: projectCode,
                    qualityDrawingId: qdid,
                    taskId: taskId,
                    executionId: entry.id,
                    body: UpdateExecutionBody(executionReply: trimmed.isEmpty ? nil : trimmed),
                    spaceId: sid
                )
            }
            if !executionEditPickedPhotos.isEmpty {
                let newFiles: [(data: Data, filename: String, mimeType: String)] = executionEditPickedPhotos
                    .prefix(maxNew)
                    .map { ($0.data, $0.filename, $0.mimeType) }
                if !newFiles.isEmpty {
                    let uploadResp = try await QualityTaskAPI.uploadExecutionAttachments(
                        projectCode: projectCode,
                        qualityDrawingId: qdid,
                        taskId: taskId,
                        executionId: entry.id,
                        attachments: newFiles,
                        spaceId: sid
                    )
                    if uploadResp.success == false {
                        showExecutionSaveNotice(uploadResp.message ?? "部分檔案上傳失敗")
                        editingLedgerExecution = nil
                        executionEditPickedPhotos = []
                        await loadAll()
                        refreshPendingExecutions()
                        return
                    }
                }
            }
            editingLedgerExecution = nil
            executionEditPickedPhotos = []
            await loadAll()
            refreshPendingExecutions()
        } catch {
            executionEditError = error.userFacingMessage
        }
    }

    private func deleteLedgerExecution(entry: TaskLedgerEntryDto) async {
        guard let sid = session.spaceId else {
            loadError = "缺少 Space。"
            return
        }
        guard let qdid = resolvedQualityDrawingId(for: detail?.task), !qdid.isEmpty else {
            loadError = "缺少平面圖資訊。"
            return
        }
        do {
            try await QualityTaskAPI.deleteExecution(
                projectCode: projectCode,
                qualityDrawingId: qdid,
                taskId: taskId,
                executionId: entry.id,
                spaceId: sid
            )
            await loadAll()
            refreshPendingExecutions()
        } catch {
            loadError = error.userFacingMessage
        }
    }

    private func loadAll() async {
        isLoading = true
        floorPlanError = nil
        loadError = nil
        offlineFloorImage = nil
        offlineMarkerReferenceSize = .zero
        defer { isLoading = false }
        guard let sid = session.spaceId else {
            let msg = "尚未選擇 Space，無法載入任務。"
            loadError = msg
            return
        }
        do {
            if network.isConnected {
                let d = try await QualityTaskAPI.taskDetail(projectCode: projectCode, taskId: taskId, spaceId: sid)
                detail = d
                try LocalTaskCache.saveDetail(d, projectCode: projectCode, taskId: taskId, context: modelContext)
                try modelContext.save()
                await loadPlanForTask(task: d.task, spaceId: sid, preferNetwork: true)
            } else {
                detail = try LocalTaskCache.loadDetail(projectCode: projectCode, taskId: taskId, context: modelContext)
                await loadPlanForTask(task: detail?.task, spaceId: sid, preferNetwork: false)
                if detail == nil {
                    loadError = "離線暫存中無此任務詳情，請先連線開啟一次任務。"
                }
            }
        } catch {
            loadError = error.userFacingMessage
            detail = try? LocalTaskCache.loadDetail(projectCode: projectCode, taskId: taskId, context: modelContext)
            await loadPlanForTask(task: detail?.task, spaceId: sid, preferNetwork: false)
        }
    }

    private func resolvedQualityDrawingId(for task: QualityTaskDto?) -> String? {
        if let id = task?.qualityDrawing?.id, !id.isEmpty { return id }
        if let hint = qualityDrawingIdHint, !hint.isEmpty { return hint }
        return cachedListRow?.drawingId
    }

    private func loadPlanForTask(task: QualityTaskDto?, spaceId: String, preferNetwork: Bool) async {
        guard let qdid = resolvedQualityDrawingId(for: task) else {
            resolvedDrawingId = nil
            floorImageURL = nil
            floorImageFallbackURL = nil
            spaceMarker = nil
            if task != nil {
                floorPlanError = "此任務未關聯平面圖。"
            }
            return
        }
        resolvedDrawingId = qdid
        await applyPlanFromCache(qualityDrawingId: qdid, task: task)

        guard preferNetwork, network.isConnected else { return }
        do {
            async let drawingTask = QualityTaskAPI.drawingDetail(
                projectCode: projectCode,
                qualityDrawingId: qdid,
                spaceId: spaceId
            )
            async let pointsTask = QualityTaskAPI.roomPoints(
                projectCode: projectCode,
                qualityDrawingId: qdid,
                spaceId: spaceId
            )
            let (drawing, pts) = try await (drawingTask, pointsTask)
            roomPoints = pts
            let (primaryURL, fallbackURL) = Self.floorImagePrimaryAndFallback(for: drawing.drawing.file)
            floorImageURL = primaryURL
            floorImageFallbackURL = fallbackURL
            if floorImageURL == nil {
                floorPlanError =
                    drawing.drawing.file == nil
                    ? "此品質圖面尚未上傳檔案，無法顯示平面圖。"
                    : "無法組出圖檔網址，請確認 API 設定。"
            } else if offlineFloorImage != nil {
                floorPlanError = nil
            }
            if let task {
                spaceMarker = resolveTaskSpaceMarker(task: task, points: pts)
            }
            if let data = await PlanAssetCache.downloadImageData(file: drawing.drawing.file, spaceId: spaceId) {
                try? await PlanAssetCache.persistImageData(
                    projectCode: projectCode,
                    qualityDrawingId: qdid,
                    imageData: data,
                    context: modelContext
                )
                await applyPlanFromCache(qualityDrawingId: qdid, task: task)
            }
        } catch {
            if offlineFloorImage == nil {
                floorPlanError = error.userFacingMessage
            }
        }
    }

    private func applyPlanFromCache(qualityDrawingId: String, task: QualityTaskDto?) async {
        await PlanAssetCache.repairCachedPNGs(projectCode: projectCode, context: modelContext)
        guard let bundle = try? PlanAssetCache.loadBundle(
            projectCode: projectCode,
            qualityDrawingId: qualityDrawingId,
            context: modelContext
        ) else { return }
        if !bundle.points.isEmpty {
            roomPoints = bundle.points
        }
        if let img = bundle.image {
            offlineFloorImage = img
            offlineMarkerReferenceSize = bundle.markerReferenceSize
            floorPlanError = nil
        } else if offlineFloorImage == nil, !bundle.points.isEmpty {
            let ref = bundle.markerReferenceSize
            offlineFloorImage = FloorPlanRasterDecoder.placeholderCanvas(markerReferenceSize: ref)
            offlineMarkerReferenceSize = ref
            if floorPlanError == nil {
                floorPlanError = "平面圖暫存尚無圖檔；請在設定確認已下載暫存。"
            }
        }
        if let task {
            spaceMarker = resolveTaskSpaceMarker(task: task, points: bundle.points)
        }
    }

    /// 主檔優先（完整 PDF／原圖），必要時再試縮圖；下載或解碼失敗時由 `SpaceAuthenticatedImageView` 自動改試備援 URL。
    private static func floorImagePrimaryAndFallback(for file: DrawingFileDto?) -> (URL?, URL?) {
        guard let file else { return (nil, nil) }
        let full = URLResolver.absoluteAssetURL(file.url)
        let thumb = URLResolver.absoluteAssetURL(file.thumbnailUrl)
        let primary = full ?? thumb
        let fallback: URL?
        if let f = full, let t = thumb, f.absoluteString != t.absoluteString {
            fallback = (primary?.absoluteString == f.absoluteString) ? t : f
        } else {
            fallback = nil
        }
        return (primary, fallback)
    }

    private func resolveTaskSpaceMarker(task: QualityTaskDto, points: [QualityTaskRoomPointDto]) -> TaskSpaceMarker? {
        let matched: QualityTaskRoomPointDto?
        let roomKey = (task.room?.id).flatMap { $0.isEmpty ? nil : $0 } ?? (task.roomId).flatMap { $0.isEmpty ? nil : $0 }
        let groupKey = (task.group?.id).flatMap { $0.isEmpty ? nil : $0 } ?? (task.groupId).flatMap { $0.isEmpty ? nil : $0 }
        if let roomId = roomKey {
            matched = points.first { $0.id == roomId }
        } else if let groupId = groupKey {
            let compositeId = "\(qualityTaskHouseholdPointIdPrefix)\(groupId)"
            matched = points.first { $0.id == compositeId || $0.groupId == groupId }
        } else {
            matched = nil
        }
        guard let p = matched else { return nil }
        let title = task.room?.name ?? task.group?.name ?? p.name
        return TaskSpaceMarker(
            x: p.x,
            y: p.y,
            title: title,
            taskCount: p.taskCount ?? 0,
            incompleteTaskCount: p.incompleteTaskCount ?? 0
        )
    }

    private func saveNewExecution(reply: String, attachments: [(data: Data, filename: String, mimeType: String)]) async -> Bool {
        guard let sid = session.spaceId else {
            loadError = "缺少 Space，無法儲存執行紀錄。"
            return false
        }
        guard let qdid = detail?.task.qualityDrawing?.id ?? resolvedDrawingId ?? qualityDrawingIdHint else {
            loadError = "無法儲存：此任務缺少平面圖資訊。"
            return false
        }
        let trimmed = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        if network.isConnected {
            do {
                let res = try await QualityTaskAPI.createExecution(
                    projectCode: projectCode,
                    qualityDrawingId: qdid,
                    taskId: taskId,
                    executionReply: trimmed.isEmpty ? nil : trimmed,
                    attachments: attachments,
                    spaceId: sid
                )
                if let w = res.uploadWarnings, !w.isEmpty {
                    loadError = w.map { "\($0.filename)：\($0.error)" }.joined(separator: "；")
                }
                executionSaveNotice = nil
                executionSaveNoticeID = nil
                await loadAll()
                refreshPendingExecutions()
                return true
            } catch {
                loadError = error.userFacingMessage
                return false
            }
        } else {
            do {
                try ExecutionOutbox.enqueue(
                    projectCode: projectCode,
                    qualityDrawingId: qdid,
                    taskId: taskId,
                    executionReply: trimmed,
                    photos: attachments,
                    context: modelContext
                )
                loadError = nil
                showExecutionSaveNotice(
                    attachments.isEmpty
                        ? "已暫存執行說明，連線後將自動上傳。"
                        : "已暫存執行說明與 \(attachments.count) 張照片，連線後將自動上傳。"
                )
                refreshPendingExecutions()
                return true
            } catch {
                loadError = error.userFacingMessage
                return false
            }
        }
    }

    private func submitCurrentExecutionsForReview() async {
        guard showCompleteSubmitEntry else {
            loadError = "僅任務執行人可完成提交，且任務需為進行中並已有一筆以上執行紀錄。"
            return
        }
        guard let sid = session.spaceId else {
            loadError = "缺少 Space，無法送出執行紀錄。"
            return
        }
        guard let task = detail?.task,
              let qdid = resolvedQualityDrawingId(for: task),
              !qdid.isEmpty
        else {
            loadError = "缺少平面圖資訊，無法送出執行紀錄。"
            return
        }

        isSubmittingExecution = true
        loadError = nil
        defer { isSubmittingExecution = false }

        do {
            _ = try await QualityTaskAPI.submitExecution(
                projectCode: projectCode,
                qualityDrawingId: qdid,
                taskId: taskId,
                spaceId: sid
            )
            showExecutionSaveNotice("執行紀錄已送出，等待審核。")
            await loadAll()
            refreshPendingExecutions()
            await notifyTaskChanged()
        } catch {
            loadError = error.userFacingMessage
        }
    }

    private func openReviewDraft(kind: ReviewKind, result: QualityTaskReviewResult) {
        reviewCommentText = ""
        reviewPickedPhotos = []
        reviewSubmitError = nil
        reviewDraft = ReviewActionDraft(kind: kind, result: result)
    }

    private func clearReviewDraft() {
        reviewDraft = nil
        reviewCommentText = ""
        reviewPickedPhotos = []
        reviewSubmitError = nil
    }

    private func submitReviewAction(draft: ReviewActionDraft) async {
        guard let sid = session.spaceId else {
            reviewSubmitError = "缺少 Space，無法送出審核。"
            return
        }
        guard let task = detail?.task else {
            reviewSubmitError = "尚未載入任務資料。"
            return
        }
        guard let qdid = resolvedQualityDrawingId(for: task), !qdid.isEmpty else {
            reviewSubmitError = "缺少平面圖資訊，無法送出審核。"
            return
        }
        guard let submissionId = detail?.latestSubmission?.id, !submissionId.isEmpty else {
            reviewSubmitError = "缺少提交資料，無法送出審核。"
            return
        }
        guard reviewCommentText.count <= 2000 else {
            reviewSubmitError = "意見最多 2000 個字。"
            return
        }

        isSubmittingReview = true
        reviewSubmitError = nil
        defer { isSubmittingReview = false }

        let trimmed = reviewCommentText.trimmingCharacters(in: .whitespacesAndNewlines)
        let files = reviewPickedPhotos.map { ($0.data, $0.filename, $0.mimeType) }

        do {
            if !files.isEmpty {
                let uploadResp: UploadReviewAttachmentsResponseDto
                switch draft.kind {
                case .director:
                    uploadResp = try await QualityTaskAPI.uploadDirectorReviewAttachments(
                        projectCode: projectCode,
                        qualityDrawingId: qdid,
                        taskId: taskId,
                        submissionId: submissionId,
                        attachments: files,
                        spaceId: sid
                    )
                case .reviewer:
                    uploadResp = try await QualityTaskAPI.uploadReviewAttachments(
                        projectCode: projectCode,
                        qualityDrawingId: qdid,
                        taskId: taskId,
                        submissionId: submissionId,
                        attachments: files,
                        spaceId: sid
                    )
                }
                if uploadResp.success == false {
                    reviewSubmitError = uploadResp.message ?? "部分附件上傳失敗，請確認後再試。"
                    return
                }
            }

            let body = ReviewSubmissionBody(
                reviewResult: draft.result,
                reviewComment: trimmed.isEmpty ? nil : trimmed
            )
            switch draft.kind {
            case .director:
                _ = try await QualityTaskAPI.directorReviewSubmission(
                    projectCode: projectCode,
                    qualityDrawingId: qdid,
                    taskId: taskId,
                    submissionId: submissionId,
                    body: body,
                    spaceId: sid
                )
            case .reviewer:
                _ = try await QualityTaskAPI.reviewSubmission(
                    projectCode: projectCode,
                    qualityDrawingId: qdid,
                    taskId: taskId,
                    submissionId: submissionId,
                    body: body,
                    spaceId: sid
                )
            }

            showExecutionSaveNotice(draft.result == .approved ? "已送出通過結果。" : "已退回任務。")
            clearReviewDraft()
            await loadAll()
            refreshPendingExecutions()
            await notifyTaskChanged()
        } catch {
            reviewSubmitError = error.userFacingMessage
        }
    }

    private func notifyTaskChanged() async {
        if let onTaskChanged {
            await onTaskChanged()
        }
    }
}

// MARK: - 平面圖縮放／平移（對齊 constructionApp `SiteRecordPlanZoomPanView`）

/// 將圖片置於 bounds 內 **aspectFit**（與網頁版、現場 App 平面圖邏輯一致）。
private func qualityTaskAspectFitImageRect(imageSize: CGSize, in bounds: CGSize) -> CGRect {
    guard imageSize.width > 0, imageSize.height > 0, bounds.width > 0, bounds.height > 0 else { return .zero }
    let ir = imageSize.width / imageSize.height
    let br = bounds.width / bounds.height
    let w: CGFloat
    let h: CGFloat
    if ir > br {
        w = bounds.width
        h = bounds.width / ir
    } else {
        h = bounds.height
        w = bounds.height * ir
    }
    let x = (bounds.width - w) / 2
    let y = (bounds.height - h) / 2
    return CGRect(x: x, y: y, width: w, height: h)
}

/// 平面圖內容座標（縮放前）→ 目前螢幕座標；與 Web `PointMarker` 位置計算一致。
private func qualityTaskPlanScreenPoint(
    local: CGPoint,
    bounds: CGSize,
    scale: CGFloat,
    offset: CGSize
) -> CGPoint {
    let cx = bounds.width / 2
    let cy = bounds.height / 2
    return CGPoint(
        x: cx + (local.x - cx) * scale + offset.width,
        y: cy + (local.y - cy) * scale + offset.height
    )
}

/// 雙指以**觸控中心**為錨點縮放（`UIPinchGestureRecognizer`）、單指平移、雙擊還原；透明 overlay 接觸控，下層圖不搶手勢。
private struct QualityTaskFloorPlanZoomPanView: View {
    let image: UIImage
    let markerReferenceSize: CGSize
    let marker: TaskSpaceMarker?

    @State private var committedScale: CGFloat = 1
    @State private var committedOffset: CGSize = .zero

    var body: some View {
        GeometryReader { geo in
            let bounds = geo.size
            let fitted = qualityTaskAspectFitImageRect(imageSize: image.size, in: bounds)
            ZStack {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: fitted.width, height: fitted.height)
                    .position(x: fitted.midX, y: fitted.midY)
                    .frame(width: bounds.width, height: bounds.height)
                    .scaleEffect(committedScale, anchor: .center)
                    .offset(committedOffset)
                    .allowsHitTesting(false)

                if let marker {
                    let (px, py) = markerNormalizedFractions(marker: marker)
                    let local = CGPoint(
                        x: fitted.minX + px * fitted.width,
                        y: fitted.minY + py * fitted.height
                    )
                    let screen = qualityTaskPlanScreenPoint(
                        local: local,
                        bounds: bounds,
                        scale: committedScale,
                        offset: committedOffset
                    )
                    taskSpaceMarkerBadge(marker: marker)
                        .position(x: screen.x, y: screen.y)
                        .allowsHitTesting(false)
                }

                QualityTaskPlanInteractionOverlay(
                    bounds: bounds,
                    scale: $committedScale,
                    offset: $committedOffset
                )
                .frame(width: bounds.width, height: bounds.height)
            }
            .clipped()
            .overlay(alignment: .bottomTrailing) {
                Text(String(format: "%.0f%%", committedScale * 100))
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .padding(10)
            }
        }
    }

    @ViewBuilder
    private func taskSpaceMarkerBadge(marker: TaskSpaceMarker) -> some View {
        let hasIncomplete = marker.incompleteTaskCount > 0
        QualityPlanPointMarker.badge(
            count: marker.taskCount,
            incomplete: hasIncomplete,
            selected: false
        )
    }

    /// 將後端／Web 畫布座標換算為在 `fitted` 內的 0…1 比例（相對於顯示用 `image.size`）。
    private func markerNormalizedFractions(marker: TaskSpaceMarker) -> (CGFloat, CGFloat) {
        let rw = markerReferenceSize.width
        let rh = markerReferenceSize.height
        guard rw > 0, rh > 0 else { return (0, 0) }
        return (CGFloat(marker.x) / rw, CGFloat(marker.y) / rh)
    }
}

// MARK: - 平面圖手勢（雙指錨點縮放）

/// 繞 `bounds` 中心縮放並帶 `offset` 時，求螢幕點 `focal` 下對應的「內容座標」（與 `planLayer` 區域對齊之座標系）。
private enum QualityTaskPlanZoomMath {
    static let minScale: CGFloat = 0.2
    static let maxScale: CGFloat = 6

    static func clampScale(_ s: CGFloat) -> CGFloat {
        min(max(s, minScale), maxScale)
    }

    /// 在 `(scale, offset)` 下，螢幕點 `focal` 對應的內容點（未縮放前以中心為原點之線性座標）。
    static func contentPoint(
        bounds: CGSize,
        focal: CGPoint,
        scale: CGFloat,
        offset: CGSize
    ) -> CGPoint {
        let cx = bounds.width / 2
        let cy = bounds.height / 2
        guard scale > 0.000_1 else { return CGPoint(x: cx, y: cy) }
        return CGPoint(
            x: cx + (focal.x - offset.width - cx) / scale,
            y: cy + (focal.y - offset.height - cy) / scale
        )
    }

    /// 縮放改為 `newScale` 後，使內容點 `content` 仍落在螢幕點 `focal` 上所需之 offset。
    static func offsetKeepingContentAtFocal(
        bounds: CGSize,
        content: CGPoint,
        focal: CGPoint,
        newScale: CGFloat
    ) -> CGSize {
        let cx = bounds.width / 2
        let cy = bounds.height / 2
        return CGSize(
            width: focal.x - cx - (content.x - cx) * newScale,
            height: focal.y - cy - (content.y - cy) * newScale
        )
    }
}

private struct QualityTaskPlanInteractionOverlay: UIViewRepresentable {
    var bounds: CGSize
    @Binding var scale: CGFloat
    @Binding var offset: CGSize

    func makeCoordinator() -> Coordinator {
        Coordinator(scale: $scale, offset: $offset)
    }

    func makeUIView(context: Context) -> UIView {
        let v = UIView()
        v.backgroundColor = .clear
        v.isMultipleTouchEnabled = true

        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePinch(_:)))
        pinch.delegate = context.coordinator
        v.addGestureRecognizer(pinch)

        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        pan.minimumNumberOfTouches = 1
        pan.maximumNumberOfTouches = 1
        pan.delegate = context.coordinator
        v.addGestureRecognizer(pan)

        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        v.addGestureRecognizer(doubleTap)
        pan.require(toFail: doubleTap)

        context.coordinator.pinch = pinch
        context.coordinator.pan = pan
        _ = doubleTap
        return v
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.boundsSize = bounds
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        @Binding var scale: CGFloat
        @Binding var offset: CGSize
        var boundsSize: CGSize = .zero

        weak var pinch: UIPinchGestureRecognizer?
        weak var pan: UIPanGestureRecognizer?

        private var pinchBaseScale: CGFloat = 1
        private var pinchBaseOffset: CGSize = .zero
        private var pinchFocal0: CGPoint = .zero
        private var pinchAnchorContent: CGPoint = .zero
        private var panStartOffset: CGSize = .zero

        init(scale: Binding<CGFloat>, offset: Binding<CGSize>) {
            _scale = scale
            _offset = offset
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            false
        }

        @objc func handlePinch(_ g: UIPinchGestureRecognizer) {
            guard let view = g.view else { return }
            let b = boundsSize
            guard b.width > 0, b.height > 0 else { return }

            switch g.state {
            case .began:
                pinchBaseScale = scale
                pinchBaseOffset = offset
                pinchFocal0 = g.location(in: view)
                pinchAnchorContent = QualityTaskPlanZoomMath.contentPoint(
                    bounds: b,
                    focal: pinchFocal0,
                    scale: pinchBaseScale,
                    offset: pinchBaseOffset
                )
            case .changed:
                let S0 = pinchBaseScale
                let S1 = QualityTaskPlanZoomMath.clampScale(S0 * g.scale)
                let focal = g.location(in: view)
                let O1 = QualityTaskPlanZoomMath.offsetKeepingContentAtFocal(
                    bounds: b,
                    content: pinchAnchorContent,
                    focal: focal,
                    newScale: S1
                )
                scale = S1
                offset = O1
            case .ended, .cancelled, .failed:
                pinchBaseScale = scale
                pinchBaseOffset = offset
            default:
                break
            }
        }

        @objc func handlePan(_ g: UIPanGestureRecognizer) {
            switch g.state {
            case .began:
                panStartOffset = offset
            case .changed:
                let t = g.translation(in: g.view)
                offset = CGSize(width: panStartOffset.width + t.x, height: panStartOffset.height + t.y)
            case .ended, .cancelled, .failed:
                panStartOffset = offset
            default:
                break
            }
        }

        @objc func handleDoubleTap(_: UITapGestureRecognizer) {
            DispatchQueue.main.async {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                    self.scale = 1
                    self.offset = .zero
                }
            }
        }
    }
}

/// 後端 `GET /files/...` 在 `requireSpaceMember` 之下，**必須**帶 `x-space-id`；`AsyncImage` 不會帶自訂 header，載入必定失敗。
/// 主 URL 若 404 或解碼失敗（例如縮圖尚未產生），會依序改試 `fallbackURL`。
private struct SpaceAuthenticatedImageView: View {
    let projectCode: String
    let qualityDrawingId: String?
    let url: URL?
    let fallbackURL: URL?
    let offlineImage: UIImage?
    let offlineMarkerReferenceSize: CGSize
    let spaceId: String?
    let marker: TaskSpaceMarker?
    @Binding var loadError: String?

    @Environment(\.modelContext) private var modelContext
    @State private var image: UIImage?
    @State private var markerReferenceSize: CGSize = .zero
    @State private var didFail = false

    /// 僅依 URL／Space 觸發下載，勿併入 `markerReferenceSize`（載入完成後會變動而導致重複請求）。
    private var loadURLIdentity: String {
        let offlineKey = offlineImage != nil ? "1" : "0"
        return "\(url?.absoluteString ?? "")|\(fallbackURL?.absoluteString ?? "")|\(spaceId ?? "")|\(offlineKey)|\(qualityDrawingId ?? "")"
    }

    /// 標記或參考尺寸變更時重置縮放視圖狀態（不重新下載二進位）。
    private var zoomPanViewIdentity: String {
        let m = marker.map { "\($0.x)|\($0.y)|\($0.title)" } ?? ""
        let ref = "\(markerReferenceSize.width)x\(markerReferenceSize.height)"
        return "\(loadURLIdentity)|\(m)|\(ref)"
    }

    var body: some View {
        Group {
            if let image {
                QualityTaskFloorPlanZoomPanView(
                    image: image,
                    markerReferenceSize: markerReferenceSize.width > 0 ? markerReferenceSize : image.size,
                    marker: marker
                )
                    .id(zoomPanViewIdentity)
            } else if didFail {
                Image(systemName: "photo")
                    .font(.largeTitle)
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.regular)
                        .tint(.secondary)
                    Text("載入平面圖…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .task(id: loadURLIdentity) { await load() }
    }

    private func load() async {
        if let offlineImage {
            let ref = offlineMarkerReferenceSize.width > 0
                ? offlineMarkerReferenceSize
                : offlineImage.size
            await MainActor.run {
                image = offlineImage
                markerReferenceSize = ref
                didFail = false
                loadError = nil
            }
            return
        }

        guard let sid = spaceId, !sid.isEmpty else {
            await MainActor.run {
                image = nil
                markerReferenceSize = .zero
                didFail = false
                loadError = "無法下載平面圖：尚未取得 Space（請確認已登入並選擇 Space）。"
            }
            return
        }

        var candidates: [URL] = []
        if let u = url { candidates.append(u) }
        if let f = fallbackURL,
           !candidates.contains(where: { $0.absoluteString == f.absoluteString })
        {
            candidates.append(f)
        }

        guard !candidates.isEmpty else {
            if await loadFromPlanCache() { return }
            await MainActor.run {
                image = nil
                markerReferenceSize = .zero
                didFail = true
                loadError = "缺少圖檔網址。"
            }
            return
        }

        await MainActor.run {
            didFail = false
            image = nil
            markerReferenceSize = .zero
            loadError = nil
        }

        var lastError: String?
        for candidate in candidates {
            do {
                let data = try await APIClient.shared.fetchBinary(url: candidate, spaceId: sid)
                let decoded = await MainActor.run(body: { FloorPlanRasterDecoder.decode(from: data) })
                if let decoded {
                    await MainActor.run {
                        image = decoded.image
                        markerReferenceSize = decoded.markerReferenceSize
                        didFail = false
                        loadError = nil
                    }
                    return
                }
                lastError = "已下載圖檔但無法顯示（可能為不支援的格式）。"
            } catch {
                lastError = error.userFacingMessage
            }
        }

        if await loadFromPlanCache() { return }

        await MainActor.run {
            image = nil
            markerReferenceSize = .zero
            didFail = true
            loadError = lastError ?? "載入平面圖失敗。"
        }
    }

    private func loadFromPlanCache() async -> Bool {
        guard let qdid = qualityDrawingId else { return false }
        await PlanAssetCache.repairCachedPNGs(projectCode: projectCode, context: modelContext)
        guard let bundle = try? PlanAssetCache.loadBundle(
            projectCode: projectCode,
            qualityDrawingId: qdid,
            context: modelContext
        ) else { return false }
        if let img = bundle.image {
            await MainActor.run {
                image = img
                markerReferenceSize = bundle.markerReferenceSize
                didFail = false
                loadError = nil
            }
            return true
        }
        if !bundle.points.isEmpty {
            let ref = bundle.markerReferenceSize
            await MainActor.run {
                image = FloorPlanRasterDecoder.placeholderCanvas(markerReferenceSize: ref)
                markerReferenceSize = ref
                didFail = false
                loadError = "平面圖暫存尚無圖檔。"
            }
            return true
        }
        return false
    }
}

private struct FloorPlanCanvasView: View {
    let projectCode: String
    let qualityDrawingId: String?
    let imageURL: URL?
    let fallbackImageURL: URL?
    let offlineImage: UIImage?
    let offlineMarkerReferenceSize: CGSize
    let spaceId: String?
    let marker: TaskSpaceMarker?
    @Binding var loadError: String?

    private var canShowPlan: Bool {
        offlineImage != nil || imageURL != nil || fallbackImageURL != nil || qualityDrawingId != nil
    }

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color(white: 0.93)
                if canShowPlan {
                    SpaceAuthenticatedImageView(
                        projectCode: projectCode,
                        qualityDrawingId: qualityDrawingId,
                        url: imageURL,
                        fallbackURL: fallbackImageURL,
                        offlineImage: offlineImage,
                        offlineMarkerReferenceSize: offlineMarkerReferenceSize,
                        spaceId: spaceId,
                        marker: marker,
                        loadError: $loadError
                    )
                        .frame(width: geo.size.width, height: geo.size.height)
                } else {
                    VStack(spacing: 8) {
                        Image(systemName: "map").font(.largeTitle).foregroundStyle(.secondary)
                        Text("無法載入平面圖（離線或未指派圖面）").font(.caption).multilineTextAlignment(.center).foregroundStyle(.secondary)
                    }
                    .padding()
                }
            }
        }
    }
}

// MARK: - Add execution（含照片；後端每筆最多 3 個附件）

private struct ExecutionAttachmentThumbnail: View {
    let attachment: ExecutionAttachmentDto
    let spaceId: String?

    @State private var image: UIImage?
    @State private var showPreview = false

    var body: some View {
        Group {
            if let image {
                Button {
                    showPreview = true
                } label: {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                }
                .buttonStyle(.plain)
                .accessibilityLabel("預覽附件")
            } else {
                ZStack {
                    Color(.systemGray5)
                    ProgressView()
                        .scaleEffect(0.75)
                }
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .task(id: attachment.id) {
            await loadImage()
        }
        .fullScreenCover(isPresented: $showPreview) {
            if let image {
                PhotoPreviewScreen(image: image) {
                    showPreview = false
                }
            }
        }
    }

    private func loadImage() async {
        guard let sid = spaceId, !sid.isEmpty else { return }
        let candidates = [attachment.thumbnailUrl, attachment.url].compactMap { URLResolver.absoluteAssetURL($0) }
        for u in candidates {
            if let data = try? await APIClient.shared.fetchBinary(url: u, spaceId: sid),
               let img = UIImage(data: data) {
                await MainActor.run { image = img }
                return
            }
        }
    }
}

private struct AddExecutionSheet: View {
    let onCancel: () -> Void
    let onSave: (String, [(data: Data, filename: String, mimeType: String)]) async -> Bool

    @Environment(NetworkPathMonitor.self) private var network
    @State private var reply = ""
    @State private var pickedPhotos: [PickedUploadPhoto] = []
    @State private var isPreparing = false
    @State private var localError: String?

    private let maxPhotos = maxExecutionAttachmentsPerEntry

    var body: some View {
        NavigationStack {
            Form {
                if !network.isConnected {
                    Section {
                        Label("離線將暫存至本機，連線後自動上傳", systemImage: "icloud.and.arrow.up")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }
                Section("執行說明") {
                    TextEditor(text: $reply)
                        .frame(minHeight: 120)
                }
                Section {
                    TaskAttachmentPhotoPickerSection(
                        photos: $pickedPhotos,
                        maxCount: maxPhotos,
                        filenamePrefix: "execution",
                        isDisabled: isPreparing,
                        caption: "與後端設定相同：每筆執行紀錄最多 \(maxPhotos) 個附件。",
                        onError: { localError = $0 }
                    )
                } header: {
                    Text("附件")
                }
                if let localError, !localError.isEmpty {
                    Section {
                        Text(localError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }
            .dismissKeyboardOnScroll()
            .keyboardDoneToolbar()
            .nobleHallFormStyle()
            .navigationTitle("新增紀錄")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(network.isConnected ? "儲存" : "暫存") {
                        localError = nil
                        Task { await prepareAndSave() }
                    }
                    .disabled(
                        isPreparing
                            || (reply.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && pickedPhotos.isEmpty)
                    )
                }
            }
        }
        .dismissKeyboardOnTapOutside()
    }

    private func prepareAndSave() async {
        await MainActor.run { isPreparing = true }
        let attachments = pickedPhotos.prefix(maxPhotos).map { ($0.data, $0.filename, $0.mimeType) }
        let text = await MainActor.run { reply }
        _ = await onSave(text, attachments)
        await MainActor.run { isPreparing = false }
    }
}
