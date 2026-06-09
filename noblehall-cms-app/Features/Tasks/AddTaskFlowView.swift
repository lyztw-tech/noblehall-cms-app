import PDFKit
import PhotosUI
import SwiftData
import SwiftUI
import UIKit
import UniformTypeIdentifiers

private let addTaskHouseholdPointIdPrefix = "qt-hh:"
private let addTaskMaxPhotoCount = 3

@ViewBuilder
private func offlineBanner(_ message: String) -> some View {
    Text(message)
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(Color.orange.opacity(0.12))
}

// MARK: - 流程入口：選圖面 → 點空間 → 填表單

/// 品質圖面選擇（FAB 第一步）
struct QualityDrawingPickerSheet: View {
    let projectCode: String
    let onSelect: (QualityDrawingListItemDto) -> Void
    let onCancel: () -> Void

    @Environment(SessionStore.self) private var session
    @Environment(NetworkPathMonitor.self) private var network
    @Environment(\.modelContext) private var modelContext

    @State private var drawings: [QualityDrawingListItemDto] = []
    @State private var loadError: String?
    @State private var isLoading = false
    @State private var usingOfflineCache = false

    var body: some View {
        NavigationStack {
            Group {
                if isLoading, drawings.isEmpty {
                    ProgressView("載入平面圖…")
                } else if let loadError, drawings.isEmpty {
                    ContentUnavailableView("無法載入", systemImage: "exclamationmark.triangle", description: Text(loadError))
                } else if drawings.isEmpty {
                    ContentUnavailableView("尚無品質圖面", systemImage: "map", description: Text(offlineEmptyHint))
                } else {
                    List(drawings) { d in
                        Button {
                            onSelect(d)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(d.drawing.name).font(.headline)
                                    if let c = d.taskCount {
                                        Text("\(c) 個任務").font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                            }
                        }
                    }
                }
            }
            .navigationTitle("選擇平面圖")
            .navigationBarTitleDisplayMode(.inline)
            .appGroupedListStyle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消", action: onCancel)
                }
            }
            .safeAreaInset(edge: .top) {
                if usingOfflineCache {
                    offlineBanner("離線模式：顯示已暫存的平面圖清單")
                }
            }
            .task { await load() }
        }
    }

    private var offlineEmptyHint: String {
        usingOfflineCache
            ? "離線暫存中尚無平面圖，請先連線並在設定中下載暫存。"
            : "請先在 Web 後台建立品質圖面。"
    }

    private func load() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }

        if network.isConnected {
            usingOfflineCache = false
            do {
                let res = try await QualityTaskAPI.listQualityDrawings(projectCode: projectCode)
                drawings = res.data
            } catch {
                loadError = error.userFacingMessage
            }
            return
        }

        usingOfflineCache = true
        let cached = (try? PlanAssetCache.listDrawingItems(projectCode: projectCode, context: modelContext)) ?? []
        if cached.isEmpty {
            loadError = "離線暫存中尚無平面圖，請先連線並在設定中下載暫存。"
        } else {
            drawings = cached
        }
    }
}

/// 新增任務：平面圖 + 所有空間點（點選後開表單）
struct AddTaskPlanScreen: View {
    let projectCode: String
    let drawing: QualityDrawingListItemDto
    let onClose: () -> Void
    let onCreated: () -> Void

    @Environment(SessionStore.self) private var session
    @Environment(NetworkPathMonitor.self) private var network
    @Environment(\.modelContext) private var modelContext

    @State private var floorImageURL: URL?
    @State private var floorImageFallbackURL: URL?
    @State private var offlineFloorImage: UIImage?
    @State private var roomPoints: [QualityTaskRoomPointDto] = []
    @State private var projectGroups: [ProjectGroupDto] = []
    @State private var markerReferenceSize: CGSize = .zero
    @State private var floorPlanError: String?
    @State private var loadError: String?
    @State private var isLoading = true
    @State private var selectedPoint: QualityTaskRoomPointDto?

    private var groupNamesById: [String: String] {
        projectGroups.reduce(into: [:]) { result, group in
            result[group.id] = group.name
        }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                AppTheme.warmBackground.ignoresSafeArea()
                if isLoading {
                    ProgressView("載入平面圖…")
                } else if let loadError {
                    ContentUnavailableView(
                        "無法載入",
                        systemImage: "wifi.slash",
                        description: Text(loadError)
                    )
                } else {
                    AddTaskFloorPlanCanvas(
                        projectCode: projectCode,
                        qualityDrawingId: drawing.id,
                        imageURL: floorImageURL,
                        fallbackImageURL: floorImageFallbackURL,
                        offlineImage: offlineFloorImage,
                        isOfflineMode: !network.isConnected,
                        markerReferenceSize: markerReferenceSize,
                        points: roomPoints,
                        groupNamesById: groupNamesById,
                        selectedPointId: selectedPoint?.id,
                        loadError: $floorPlanError,
                        onPointSelected: { point in
                            selectedPoint = point
                        }
                    )
                    if let floorPlanError {
                        VStack {
                            Text(floorPlanError)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .padding(8)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                                .padding()
                            Spacer()
                        }
                    }
                }
            }
            .navigationTitle(drawing.drawing.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("關閉", action: onClose)
                }
            }
            .safeAreaInset(edge: .top) {
                if !network.isConnected {
                    offlineBanner("離線模式：任務將暫存，連線後自動建立")
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !isLoading {
                    Text("點選空間座標以新增任務")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial)
                }
            }
            .sheet(item: $selectedPoint) { point in
                CreateTaskFormSheet(
                    projectCode: projectCode,
                    qualityDrawingId: drawing.id,
                    drawingName: drawing.drawing.name,
                    point: point,
                    groupNamesById: groupNamesById,
                    onCancel: { selectedPoint = nil },
                    onCreated: {
                        selectedPoint = nil
                        onCreated()
                        onClose()
                    }
                )
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
            }
            .task { await loadPlan() }
        }
        .appScreen()
    }

    private func loadPlan() async {
        isLoading = true
        loadError = nil
        floorPlanError = nil
        defer { isLoading = false }

        if !network.isConnected {
            await PlanAssetCache.repairCachedPNGs(projectCode: projectCode, context: modelContext)
            guard let bundle = try? PlanAssetCache.loadBundle(
                projectCode: projectCode,
                qualityDrawingId: drawing.id,
                context: modelContext
            ), !bundle.points.isEmpty else {
                loadError = "離線暫存中無此平面圖，請先連線並在設定中下載暫存。"
                return
            }
            roomPoints = bundle.points
            projectGroups = (try? AddTaskFormCache.load(projectCode: projectCode, context: modelContext))?.groups ?? []
            markerReferenceSize = bundle.markerReferenceSize
            floorImageURL = nil
            floorImageFallbackURL = nil
            if let img = bundle.image {
                offlineFloorImage = img
            } else {
                offlineFloorImage = FloorPlanRasterDecoder.placeholderCanvas(
                    markerReferenceSize: bundle.markerReferenceSize
                )
                floorPlanError = "此圖面暫存尚無圖檔。請先連線，在設定按「重新下載暫存」，或連線時開啟此圖面一次。"
            }
            return
        }

        do {
            async let drawingTask = QualityTaskAPI.drawingDetail(
                projectCode: projectCode,
                qualityDrawingId: drawing.id
            )
            async let pointsTask = QualityTaskAPI.roomPoints(
                projectCode: projectCode,
                qualityDrawingId: drawing.id
            )
            let (detail, pts) = try await (drawingTask, pointsTask)
            roomPoints = pts
            projectGroups = await loadProjectGroups()
            offlineFloorImage = nil
            let (primary, fallback) = Self.floorURLs(for: detail.drawing.file)
            floorImageURL = primary
            floorImageFallbackURL = fallback
            if floorImageURL == nil {
                floorPlanError = "此圖面尚未上傳檔案。"
            }
            Task {
                if let data = await PlanAssetCache.downloadImageData(file: detail.drawing.file) {
                    try? await PlanAssetCache.persistImageData(
                        projectCode: projectCode,
                        qualityDrawingId: drawing.id,
                        imageData: data,
                        context: modelContext
                    )
                }
            }
        } catch {
            loadError = error.userFacingMessage
        }
    }

    private func loadProjectGroups() async -> [ProjectGroupDto] {
        do {
            return try await QualityTaskAPI.drawingGroups(projectCode: projectCode, qualityDrawingId: drawing.id)
        } catch {
            return []
        }
    }

    private static func floorURLs(for file: DrawingFileDto?) -> (URL?, URL?) {
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
}

// MARK: - 新增任務表單（Bottom Sheet）

private struct CreateTaskFormSheet: View {
    let projectCode: String
    let qualityDrawingId: String
    let drawingName: String
    let point: QualityTaskRoomPointDto
    let groupNamesById: [String: String]
    let onCancel: () -> Void
    let onCreated: () -> Void

    @Environment(SessionStore.self) private var session
    @Environment(NetworkPathMonitor.self) private var network
    @Environment(\.modelContext) private var modelContext

    @State private var name = ""
    @State private var description = ""
    @State private var priority = "medium"
    @State private var reviewerId = ""
    @State private var executorUserId = ""
    @State private var categoryId = ""
    @State private var dueDate = Date()
    @State private var includeDueDate = false

    @State private var members: [ProjectMemberDto] = []
    @State private var groups: [ProjectGroupDto] = []
    @State private var categories: [DropdownOptionItemDto] = []
    @State private var projectId: String?

    @State private var pickedPhotos: [PickedUploadPhoto] = []

    @State private var loadError: String?
    @State private var submitError: String?
    @State private var submitSuccess: String?
    @State private var isLoadingMeta = true
    @State private var isSubmitting = false

    private var isHouseholdPoint: Bool {
        point.id.hasPrefix(addTaskHouseholdPointIdPrefix)
    }

    private var resolvedRoomId: String? {
        isHouseholdPoint ? nil : point.id
    }

    private var resolvedGroupId: String? {
        if isHouseholdPoint {
            return point.groupId ?? String(point.id.dropFirst(addTaskHouseholdPointIdPrefix.count))
        }
        return point.groupId
    }

    private var groupDisplayName: String? {
        guard let gid = resolvedGroupId, !gid.isEmpty else { return nil }
        if let groupName = groups.first(where: { $0.id == gid })?.name, !groupName.isEmpty {
            return groupName
        }
        if let groupName = groupNamesById[gid]?.trimmingCharacters(in: .whitespacesAndNewlines), !groupName.isEmpty {
            return groupName
        }
        return isLoadingMeta ? "載入中…" : nil
    }

    private var roomDisplayName: String? {
        guard !isHouseholdPoint else { return nil }
        let roomName = point.name.trimmingCharacters(in: .whitespacesAndNewlines)
        return roomName.isEmpty ? nil : roomName
    }

    private var siteStaffMembers: [ProjectMemberDto] {
        let siteMembers = members.filter { $0.memberCategory == "site" }
        return siteMembers.isEmpty ? members : siteMembers
    }

    private var reviewerOptions: [ProjectMemberDto] {
        members
    }

    var body: some View {
        NavigationStack {
            Form {
                if let loadError {
                    Section {
                        Text(loadError).foregroundStyle(.red).font(.footnote)
                    }
                }
                Section("空間") {
                    if let groupDisplayName {
                        LabeledContent("群組", value: groupDisplayName)
                    }
                    if let roomDisplayName {
                        LabeledContent("空間", value: roomDisplayName)
                    }
                }
                Section("任務內容") {
                    TextField("任務名稱 *", text: $name)
                    TextField("說明", text: $description, axis: .vertical)
                        .lineLimit(3 ... 6)
                    Picker("優先級", selection: $priority) {
                        Text("低").tag("low")
                        Text("中").tag("medium")
                        Text("高").tag("high")
                    }
                    if !categories.isEmpty {
                        Picker("類別", selection: $categoryId) {
                            Text("（不選）").tag("")
                            ForEach(categories) { c in
                                Text(c.value).tag(c.id)
                            }
                        }
                    }
                }
                Section("人員") {
                    Picker("審核人員 *", selection: $reviewerId) {
                        Text("請選擇").tag("")
                        ForEach(reviewerOptions, id: \.user.id) { m in
                            Text(m.user.displayName ?? m.user.username ?? m.user.id).tag(m.user.id)
                        }
                    }
                    Picker("執行人", selection: $executorUserId) {
                        Text("請選擇").tag("")
                        ForEach(siteStaffMembers, id: \.user.id) { m in
                            Text(m.user.displayName ?? m.user.username ?? m.user.id).tag(m.user.id)
                        }
                    }
                }
                Section("到期日") {
                    Toggle("設定到期日", isOn: $includeDueDate)
                    if includeDueDate {
                        DatePicker("到期日", selection: $dueDate, displayedComponents: [.date, .hourAndMinute])
                    }
                }
                Section("照片（最多 \(addTaskMaxPhotoCount) 張）") {
                    TaskAttachmentPhotoPickerSection(
                        photos: $pickedPhotos,
                        maxCount: addTaskMaxPhotoCount,
                        filenamePrefix: "task",
                        onError: { submitError = $0 }
                    )
                }
                if let submitSuccess {
                    Section {
                        Text(submitSuccess).foregroundStyle(.green).font(.footnote)
                    }
                }
                if let submitError {
                    Section {
                        Text(submitError).foregroundStyle(.red).font(.footnote)
                    }
                }
            }
            .dismissKeyboardOnScroll()
            .keyboardDoneToolbar()
            .appFormStyle()
            .navigationTitle("新增任務")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("新增") {
                        Task { await submit() }
                    }
                    .disabled(isSubmitting || isLoadingMeta)
                }
            }
            .overlay {
                if isLoadingMeta { ProgressView().padding() }
            }
            .task { await loadMeta() }
        }
        .dismissKeyboardOnTapOutside()
    }

    private func loadMeta() async {
        isLoadingMeta = true
        loadError = nil
        defer { isLoadingMeta = false }

        if !network.isConnected {
            if let cached = try? AddTaskFormCache.load(projectCode: projectCode, context: modelContext) {
                applyFormMeta(cached)
            } else {
                loadError = "離線無法載入表單資料，請先連線並在設定中下載暫存。"
            }
            return
        }

        do {
            async let mem = QualityTaskAPI.allProjectMembers(projectCode: projectCode)
            async let grp = QualityTaskAPI.listProjectGroups(projectCode: projectCode)
            let (memList, grpRes) = try await (mem, grp)
            projectId = projectCode
            members = memList
            groups = grpRes.data
            if let cats = try? await QualityTaskAPI.categoryOptions(projectId: projectCode) {
                categories = cats.options
            }
            try? AddTaskFormCache.save(
                projectCode: projectCode,
                projectUUID: projectCode,
                members: memList,
                groups: grpRes.data,
                categories: categories,
                context: modelContext
            )
            applyDefaultReviewer()
        } catch {
            loadError = error.userFacingMessage
        }
    }

    private func applyFormMeta(_ cached: CachedAddTaskFormData) {
        projectId = cached.projectUUID
        members = cached.members
        groups = cached.groups
        categories = cached.categories
        applyDefaultReviewer()
    }

    private func applyDefaultReviewer() {
        guard reviewerId.isEmpty, let uid = session.currentUser?.id else { return }
        if members.contains(where: { $0.user.id == uid }) {
            reviewerId = uid
        }
    }

    private func submit() async {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            submitError = "請填寫任務名稱。"
            return
        }
        guard !reviewerId.isEmpty else {
            submitError = "請選擇審核人員。"
            return
        }

        var dueISO: String?
        if includeDueDate {
            dueISO = ISO8601DateFormatter().string(from: dueDate)
        }

        let body = CreateQualityTaskBody(
            name: trimmedName,
            description: description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? nil
                : description.trimmingCharacters(in: .whitespacesAndNewlines),
            categoryId: categoryId.isEmpty ? nil : categoryId,
            groupId: resolvedGroupId,
            roomId: resolvedRoomId,
            executorId: executorUserId.isEmpty ? nil : executorUserId,
            executorType: executorUserId.isEmpty ? nil : "user",
            reviewerId: reviewerId,
            priority: priority,
            dueDate: dueISO
        )

        isSubmitting = true
        submitError = nil
        submitSuccess = nil
        defer { isSubmitting = false }

        if !network.isConnected {
            do {
                try TaskCreateOutbox.enqueue(
                    projectCode: projectCode,
                    qualityDrawingId: qualityDrawingId,
                    drawingName: drawingName,
                    body: body,
                    photos: pickedPhotos.map { ($0.data, $0.filename) },
                    context: modelContext
                )
                submitSuccess = "已暫存離線任務，連線後將自動建立。"
                try? await Task.sleep(nanoseconds: 800_000_000)
                onCreated()
            } catch {
                submitError = error.userFacingMessage
            }
            return
        }

        do {
            let created = try await QualityTaskAPI.createTask(
                projectCode: projectCode,
                qualityDrawingId: qualityDrawingId,
                body: body
            )
            if !pickedPhotos.isEmpty {
                let attachments = pickedPhotos.map { ($0.data, $0.filename, "image/jpeg") }
                try await QualityTaskAPI.uploadTaskAttachments(
                    projectCode: projectCode,
                    qualityDrawingId: qualityDrawingId,
                    taskId: created.id,
                    attachments: attachments
                )
            }
            onCreated()
        } catch {
            submitError = error.userFacingMessage
        }
    }
}

// MARK: - 平面圖（多點可點選）

private struct AddTaskFloorPlanCanvas: View {
    let projectCode: String
    let qualityDrawingId: String
    let imageURL: URL?
    let fallbackImageURL: URL?
    let offlineImage: UIImage?
    let isOfflineMode: Bool
    let markerReferenceSize: CGSize
    let points: [QualityTaskRoomPointDto]
    let groupNamesById: [String: String]
    let selectedPointId: String?
    @Binding var loadError: String?
    let onPointSelected: (QualityTaskRoomPointDto) -> Void

    var body: some View {
        GeometryReader { geo in
            AddTaskAuthenticatedPlanView(
                projectCode: projectCode,
                qualityDrawingId: qualityDrawingId,
                url: imageURL,
                fallbackURL: fallbackImageURL,
                offlineImage: offlineImage,
                isOfflineMode: isOfflineMode,
                offlineRefSize: markerReferenceSize,
                markerReferenceSize: markerReferenceSize,
                points: points,
                groupNamesById: groupNamesById,
                selectedPointId: selectedPointId,
                loadError: $loadError,
                onPointSelected: onPointSelected
            )
            .frame(width: geo.size.width, height: geo.size.height)
        }
    }
}

private struct AddTaskAuthenticatedPlanView: View {
    let projectCode: String
    let qualityDrawingId: String
    let url: URL?
    let fallbackURL: URL?
    let offlineImage: UIImage?
    let isOfflineMode: Bool
    let offlineRefSize: CGSize
    let markerReferenceSize: CGSize
    let points: [QualityTaskRoomPointDto]
    let groupNamesById: [String: String]
    let selectedPointId: String?
    @Binding var loadError: String?
    let onPointSelected: (QualityTaskRoomPointDto) -> Void

    @Environment(\.modelContext) private var modelContext
    @State private var image: UIImage?
    @State private var refSize: CGSize = .zero
    @State private var didFail = false

    private var identity: String {
        "\(url?.absoluteString ?? "")|\(offlineImage != nil)|\(points.count)|\(groupNamesById.count)|\(selectedPointId ?? "")"
    }

    var body: some View {
        Group {
            if let image {
                AddTaskZoomablePlanView(
                    image: image,
                    markerReferenceSize: refSize.width > 0 ? refSize : image.size,
                    points: points,
                    groupNamesById: groupNamesById,
                    selectedPointId: selectedPointId,
                    onPointSelected: onPointSelected
                )
            } else if didFail {
                ContentUnavailableView("無法載入平面圖", systemImage: "photo")
            } else {
                ProgressView("載入平面圖…")
            }
        }
        .task(id: identity) { await load() }
    }

    private func load() async {
        if let offlineImage {
            let ref = offlineRefSize.width > 0 ? offlineRefSize : offlineImage.size
            await MainActor.run {
                image = offlineImage
                refSize = ref
                didFail = false
                loadError = nil
            }
            return
        }
        if isOfflineMode {
            if !points.isEmpty {
                let ref = FloorPlanRasterDecoder.effectiveMarkerReferenceSize(
                    points: points,
                    stored: markerReferenceSize
                )
                await MainActor.run {
                    image = FloorPlanRasterDecoder.placeholderCanvas(markerReferenceSize: ref)
                    refSize = ref
                    didFail = false
                    loadError = "此圖面暫存尚無圖檔，仍可依座標點新增任務。"
                }
                return
            }
            await MainActor.run {
                didFail = true
                loadError = "離線暫存中無此平面圖。"
            }
            return
        }
        var candidates: [URL] = []
        if let u = url { candidates.append(u) }
        if let f = fallbackURL, !candidates.contains(where: { $0.absoluteString == f.absoluteString }) {
            candidates.append(f)
        }
        guard !candidates.isEmpty else {
            await MainActor.run { didFail = true; loadError = "缺少圖檔網址。" }
            return
        }
        await MainActor.run { image = nil; didFail = false; loadError = nil }
        for candidate in candidates {
            do {
                let data = try await APIClient.shared.fetchBinary(url: candidate)
                if let decoded = await MainActor.run(body: { FloorPlanRasterDecoder.decode(from: data) }) {
                    await MainActor.run {
                        image = decoded.image
                        refSize = decoded.markerReferenceSize
                    }
                    try? await PlanAssetCache.persistImageData(
                        projectCode: projectCode,
                        qualityDrawingId: qualityDrawingId,
                        imageData: data,
                        context: modelContext
                    )
                    return
                }
            } catch {
                await MainActor.run { loadError = error.userFacingMessage }
            }
        }
        await MainActor.run { didFail = true }
    }
}

/// 平面圖內容座標（縮放前、與 `fitted` 對齊）→ 目前螢幕座標。
private func addTaskPlanScreenPoint(
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

private let addTaskClusterScaleThreshold: CGFloat = 1.55

private struct AddTaskProjectedPlanPoint: Identifiable {
    let point: QualityTaskRoomPointDto
    let screen: CGPoint

    var id: String { point.id }
}

private struct AddTaskPlanPointCluster: Identifiable {
    let id: String
    let screen: CGPoint
    let points: [AddTaskProjectedPlanPoint]
    let representative: QualityTaskRoomPointDto
    let label: String

    var spaceCount: Int {
        let spaces = points.filter { !addTaskIsGroupPoint($0.point) }
        return spaces.isEmpty ? points.count : spaces.count
    }

    var hasIncompleteTask: Bool {
        points.contains { ($0.point.incompleteTaskCount ?? 0) > 0 }
    }

    func contains(pointId: String?) -> Bool {
        guard let pointId else { return false }
        return points.contains { $0.point.id == pointId }
    }
}

private struct AddTaskZoomablePlanView: View {
    let image: UIImage
    let markerReferenceSize: CGSize
    let points: [QualityTaskRoomPointDto]
    let groupNamesById: [String: String]
    let selectedPointId: String?
    let onPointSelected: (QualityTaskRoomPointDto) -> Void

    @State private var scale: CGFloat = 1
    @State private var offset: CGSize = .zero

    var body: some View {
        GeometryReader { geo in
            let bounds = geo.size
            let fitted = addTaskAspectFitRect(imageSize: image.size, in: bounds)
            let projectedPoints = addTaskProjectedPlanPoints(
                points: points,
                fitted: fitted,
                bounds: bounds,
                scale: scale,
                offset: offset,
                markerReferenceSize: markerReferenceSize
            )
            let shouldCluster = scale < addTaskClusterScaleThreshold
            let detailedPoints = addTaskDetailedPlanPoints(from: projectedPoints)
            ZStack {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(width: fitted.width, height: fitted.height)
                    .position(x: fitted.midX, y: fitted.midY)
                    .frame(width: bounds.width, height: bounds.height)
                    .scaleEffect(scale, anchor: .center)
                    .offset(offset)
                    .allowsHitTesting(false)

                Group {
                    if shouldCluster {
                        ForEach(addTaskPlanPointClusters(from: projectedPoints, groupNamesById: groupNamesById)) { cluster in
                            if cluster.spaceCount <= 1,
                               let single = addTaskDetailedPlanPoints(from: cluster.points).first {
                                let p = single.point
                                QualityPlanPointMarker.badge(
                                    count: p.taskCount ?? 0,
                                    incomplete: (p.incompleteTaskCount ?? 0) > 0,
                                    selected: p.id == selectedPointId
                                )
                                .position(x: single.screen.x, y: single.screen.y)
                            } else {
                                QualityPlanPointMarker.clusterBadge(
                                    label: cluster.label,
                                    incomplete: cluster.hasIncompleteTask,
                                    selected: cluster.contains(pointId: selectedPointId)
                                )
                                .position(x: cluster.screen.x, y: cluster.screen.y)
                            }
                        }
                    } else {
                        ForEach(detailedPoints) { projected in
                            let p = projected.point
                            QualityPlanPointMarker.badge(
                                count: p.taskCount ?? 0,
                                incomplete: (p.incompleteTaskCount ?? 0) > 0,
                                selected: p.id == selectedPointId
                            )
                            .position(x: projected.screen.x, y: projected.screen.y)
                        }
                    }
                }
                .allowsHitTesting(false)

                AddTaskPlanGestureOverlay(
                    bounds: bounds,
                    fitted: fitted,
                    markerReferenceSize: markerReferenceSize,
                    points: points,
                    scale: $scale,
                    offset: $offset,
                    onPointSelected: onPointSelected
                )
            }
            .clipped()
        }
    }
}

// MARK: - 手勢 / 座標 / 解碼

private func addTaskIsGroupPoint(_ point: QualityTaskRoomPointDto) -> Bool {
    point.id.hasPrefix(addTaskHouseholdPointIdPrefix)
}

private func addTaskDetailedPlanPoints(from points: [AddTaskProjectedPlanPoint]) -> [AddTaskProjectedPlanPoint] {
    let spacePoints = points.filter { !addTaskIsGroupPoint($0.point) }
    return spacePoints.isEmpty ? points : spacePoints
}

private func addTaskProjectedPlanPoints(
    points: [QualityTaskRoomPointDto],
    fitted: CGRect,
    bounds: CGSize,
    scale: CGFloat,
    offset: CGSize,
    markerReferenceSize: CGSize
) -> [AddTaskProjectedPlanPoint] {
    points.map { point in
        let frac = addTaskPointFraction(x: point.x, y: point.y, ref: markerReferenceSize)
        let local = CGPoint(
            x: fitted.minX + frac.x * fitted.width,
            y: fitted.minY + frac.y * fitted.height
        )
        let screen = addTaskPlanScreenPoint(
            local: local,
            bounds: bounds,
            scale: scale,
            offset: offset
        )
        return AddTaskProjectedPlanPoint(point: point, screen: screen)
    }
}

private func addTaskPlanPointClusters(
    from points: [AddTaskProjectedPlanPoint],
    groupNamesById: [String: String]
) -> [AddTaskPlanPointCluster] {
    let grouped = Dictionary(grouping: points) { projected in
        if let groupId = projected.point.groupId, !groupId.isEmpty {
            return "group:\(groupId)"
        }
        return "space:\(projected.point.id)"
    }

    return grouped.compactMap { key, values in
        guard let representative = addTaskClusterRepresentative(from: values) else { return nil }
        let anchor = values.first(where: { addTaskIsGroupPoint($0.point) })?.screen
            ?? addTaskAverageScreenPoint(values.map(\.screen))
        let label = addTaskClusterLabel(
            key: key,
            values: values,
            groupNamesById: groupNamesById
        )
        return AddTaskPlanPointCluster(
            id: key,
            screen: anchor,
            points: values,
            representative: representative.point,
            label: label
        )
    }
    .sorted { lhs, rhs in
        if lhs.screen.y == rhs.screen.y {
            return lhs.screen.x < rhs.screen.x
        }
        return lhs.screen.y < rhs.screen.y
    }
}

private func addTaskClusterLabel(
    key: String,
    values: [AddTaskProjectedPlanPoint],
    groupNamesById: [String: String]
) -> String {
    if key.hasPrefix("group:"),
       let groupId = values.compactMap({ $0.point.groupId }).first(where: { !$0.isEmpty }),
       let name = groupNamesById[groupId]?.trimmingCharacters(in: .whitespacesAndNewlines),
       !name.isEmpty {
        return name
    }

    if let groupPointName = values
        .first(where: { addTaskIsGroupPoint($0.point) })?
        .point
        .name
        .trimmingCharacters(in: .whitespacesAndNewlines),
        !groupPointName.isEmpty {
        return groupPointName
    }

    return "群組"
}

private func addTaskClusterRepresentative(from points: [AddTaskProjectedPlanPoint]) -> AddTaskProjectedPlanPoint? {
    if let groupPoint = points.first(where: { addTaskIsGroupPoint($0.point) }) {
        return groupPoint
    }
    let anchor = addTaskAverageScreenPoint(points.map(\.screen))
    return points.min { lhs, rhs in
        hypot(lhs.screen.x - anchor.x, lhs.screen.y - anchor.y) < hypot(rhs.screen.x - anchor.x, rhs.screen.y - anchor.y)
    }
}

private func addTaskAverageScreenPoint(_ points: [CGPoint]) -> CGPoint {
    guard !points.isEmpty else { return .zero }
    let sum = points.reduce(CGPoint.zero) { partial, point in
        CGPoint(x: partial.x + point.x, y: partial.y + point.y)
    }
    return CGPoint(x: sum.x / CGFloat(points.count), y: sum.y / CGFloat(points.count))
}

private func addTaskAspectFitRect(imageSize: CGSize, in bounds: CGSize) -> CGRect {
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
    return CGRect(x: (bounds.width - w) / 2, y: (bounds.height - h) / 2, width: w, height: h)
}

private func addTaskPointFraction(x: Double, y: Double, ref: CGSize) -> CGPoint {
    addTaskPointFractionCGFloat(x: x, y: y, ref: ref)
}

private func addTaskPointFractionCGFloat(x: Double, y: Double, ref: CGSize) -> CGPoint {
    let mx = CGFloat(x)
    let my = CGFloat(y)
    if mx >= 0, my >= 0, mx <= 1, my <= 1 { return CGPoint(x: mx, y: my) }
    guard ref.width > 0, ref.height > 0 else { return .zero }
    return CGPoint(x: mx / ref.width, y: my / ref.height)
}

private struct AddTaskPlanGestureOverlay: UIViewRepresentable {
    var bounds: CGSize
    var fitted: CGRect
    var markerReferenceSize: CGSize
    var points: [QualityTaskRoomPointDto]
    @Binding var scale: CGFloat
    @Binding var offset: CGSize
    var onPointSelected: (QualityTaskRoomPointDto) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(scale: $scale, offset: $offset, onPointSelected: onPointSelected)
    }

    func makeUIView(context: Context) -> UIView {
        let v = UIView()
        v.backgroundColor = .clear
        v.isMultipleTouchEnabled = true

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tap.delegate = context.coordinator
        v.addGestureRecognizer(tap)

        let pinch = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pinch(_:)))
        pinch.delegate = context.coordinator
        v.addGestureRecognizer(pinch)

        let pan = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.pan(_:)))
        pan.maximumNumberOfTouches = 1
        pan.delegate = context.coordinator
        v.addGestureRecognizer(pan)

        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        v.addGestureRecognizer(doubleTap)

        tap.require(toFail: pan)
        tap.require(toFail: doubleTap)
        pan.require(toFail: doubleTap)
        return v
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.boundsSize = bounds
        context.coordinator.fitted = fitted
        context.coordinator.markerReferenceSize = markerReferenceSize
        context.coordinator.points = points
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        @Binding var scale: CGFloat
        @Binding var offset: CGSize
        var onPointSelected: (QualityTaskRoomPointDto) -> Void
        var boundsSize: CGSize = .zero
        var fitted: CGRect = .zero
        var markerReferenceSize: CGSize = .zero
        var points: [QualityTaskRoomPointDto] = []

        private var baseScale: CGFloat = 1
        private var baseOffset: CGSize = .zero
        private var anchorContent: CGPoint = .zero
        private var panStart: CGSize = .zero

        init(scale: Binding<CGFloat>, offset: Binding<CGSize>, onPointSelected: @escaping (QualityTaskRoomPointDto) -> Void) {
            _scale = scale
            _offset = offset
            self.onPointSelected = onPointSelected
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            // 縮放與平移互斥：避免雙指縮放時同時觸發平移造成畫面抖動。
            false
        }

        @objc func handleTap(_ g: UITapGestureRecognizer) {
            guard g.state == .ended, let view = g.view else { return }
            let tap = g.location(in: view)
            guard let hit = nearestPoint(to: tap) else { return }
            DispatchQueue.main.async { self.onPointSelected(hit) }
        }

        private func nearestPoint(to tap: CGPoint) -> QualityTaskRoomPointDto? {
            guard fitted.width > 0, fitted.height > 0, !points.isEmpty else { return nil }
            let projected = addTaskProjectedPlanPoints(
                points: points,
                fitted: fitted,
                bounds: boundsSize,
                scale: scale,
                offset: offset,
                markerReferenceSize: markerReferenceSize
            )
            if scale < addTaskClusterScaleThreshold {
                return nearestVisibleSpacePointAtClusterScale(to: tap, projected: projected)
            }

            let candidates = addTaskDetailedPlanPoints(from: projected)
            var best: QualityTaskRoomPointDto?
            var bestDist: CGFloat = .greatestFiniteMagnitude
            let hitRadius: CGFloat = 44

            for candidate in candidates {
                let d = hypot(tap.x - candidate.screen.x, tap.y - candidate.screen.y)
                if d < bestDist {
                    bestDist = d
                    best = candidate.point
                }
            }
            return bestDist <= hitRadius ? best : nil
        }

        private func nearestVisibleSpacePointAtClusterScale(
            to tap: CGPoint,
            projected: [AddTaskProjectedPlanPoint]
        ) -> QualityTaskRoomPointDto? {
            var best: AddTaskProjectedPlanPoint?
            var bestDist: CGFloat = .greatestFiniteMagnitude
            let hitRadius: CGFloat = 44

            for cluster in addTaskPlanPointClusters(from: projected, groupNamesById: [:]) {
                guard cluster.spaceCount <= 1,
                      let visiblePoint = addTaskDetailedPlanPoints(from: cluster.points).first else {
                    continue
                }
                let d = hypot(tap.x - visiblePoint.screen.x, tap.y - visiblePoint.screen.y)
                if d < bestDist {
                    bestDist = d
                    best = visiblePoint
                }
            }
            return bestDist <= hitRadius ? best?.point : nil
        }

        @objc func pinch(_ g: UIPinchGestureRecognizer) {
            guard let view = g.view, boundsSize.width > 0 else { return }
            let b = boundsSize
            switch g.state {
            case .began:
                baseScale = scale
                baseOffset = offset
                let f0 = g.location(in: view)
                anchorContent = addTaskContentPoint(bounds: b, focal: f0, scale: baseScale, offset: baseOffset)
            case .changed:
                let s1 = min(max(baseScale * g.scale, 0.5), 6)
                let f = g.location(in: view)
                offset = addTaskOffsetKeeping(bounds: b, content: anchorContent, focal: f, newScale: s1)
                scale = s1
            default:
                baseScale = scale
                baseOffset = offset
            }
        }

        @objc func pan(_ g: UIPanGestureRecognizer) {
            switch g.state {
            case .began: panStart = offset
            case .changed:
                let t = g.translation(in: g.view)
                offset = CGSize(width: panStart.width + t.x, height: panStart.height + t.y)
            case .ended: panStart = offset
            default: break
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

private func addTaskContentPoint(bounds: CGSize, focal: CGPoint, scale: CGFloat, offset: CGSize) -> CGPoint {
    let cx = bounds.width / 2
    let cy = bounds.height / 2
    guard scale > 0.0001 else { return CGPoint(x: cx, y: cy) }
    return CGPoint(
        x: cx + (focal.x - offset.width - cx) / scale,
        y: cy + (focal.y - offset.height - cy) / scale
    )
}

private func addTaskOffsetKeeping(bounds: CGSize, content: CGPoint, focal: CGPoint, newScale: CGFloat) -> CGSize {
    let cx = bounds.width / 2
    let cy = bounds.height / 2
    return CGSize(
        width: focal.x - cx - (content.x - cx) * newScale,
        height: focal.y - cy - (content.y - cy) * newScale
    )
}
