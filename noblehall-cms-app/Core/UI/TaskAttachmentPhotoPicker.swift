import PhotosUI
import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// 已選擇、可預覽並上傳的照片（JPEG）。
struct PickedUploadPhoto: Identifiable, Hashable {
    let id: UUID
    let image: UIImage
    let data: Data
    let filename: String
    let mimeType: String

    init(id: UUID = UUID(), image: UIImage, data: Data, filename: String, mimeType: String = "image/jpeg") {
        self.id = id
        self.image = image
        self.data = data
        self.filename = filename
        self.mimeType = mimeType
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    static func == (lhs: PickedUploadPhoto, rhs: PickedUploadPhoto) -> Bool {
        lhs.id == rhs.id
    }
}

/// 已上傳的既有附件參照；編輯時與新選照片並列在同一個選擇器內顯示。
struct ExistingAttachmentRef: Identifiable, Hashable {
    let id: String
    let thumbnailURL: URL?
    let fullURL: URL?
}

enum PhotoUploadProcessing {
    private struct PickedUIImageTransfer: Transferable {
        let uiImage: UIImage

        static var transferRepresentation: some TransferRepresentation {
            DataRepresentation(importedContentType: UTType.image) { data in
                guard let img = UIImage(data: data) else {
                    throw NSError(
                        domain: "PhotoUpload",
                        code: -1,
                        userInfo: [NSLocalizedDescriptionKey: "無法解碼所選照片"]
                    )
                }
                return PickedUIImageTransfer(uiImage: img)
            }
        }
    }

    static func pickedPhoto(from uiImage: UIImage, filenamePrefix: String) throws -> PickedUploadPhoto {
        let resized = uiImage.resizedForUpload(maxLongEdge: 2400)
        guard let jpeg = resized.jpegData(compressionQuality: 0.86) else {
            throw NSError(
                domain: "PhotoUpload",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "無法產生照片資料"]
            )
        }
        let name = "\(filenamePrefix)-\(UUID().uuidString.prefix(8)).jpg"
        return PickedUploadPhoto(image: resized, data: jpeg, filename: name)
    }

    static func pickedPhoto(from item: PhotosPickerItem, filenamePrefix: String) async throws -> PickedUploadPhoto {
        let ui: UIImage
        if let picked = try await item.loadTransferable(type: PickedUIImageTransfer.self) {
            ui = picked.uiImage
        } else if let data = try await item.loadTransferable(type: Data.self), let img = UIImage(data: data) {
            ui = img
        } else {
            throw NSError(
                domain: "PhotoUpload",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "無法讀取所選照片"]
            )
        }
        return try pickedPhoto(from: ui, filenamePrefix: filenamePrefix)
    }
}

extension UIImage {
    func resizedForUpload(maxLongEdge: CGFloat) -> UIImage {
        let w = size.width * scale
        let h = size.height * scale
        let long = max(w, h)
        guard long > maxLongEdge else { return self }
        let ratio = maxLongEdge / long
        let nw = max(1, floor(w * ratio))
        let nh = max(1, floor(h * ratio))
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: nw, height: nh), format: format)
        return renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: CGSize(width: nw, height: nh)))
        }
    }
}

/// 單一按鈕：拍照或從相簿選擇；下方橫向縮圖，點擊可全螢幕預覽。
struct TaskAttachmentPhotoPickerSection: View {
    @Binding var photos: [PickedUploadPhoto]
    let maxCount: Int
    let filenamePrefix: String
    var isDisabled: Bool = false
    var caption: String?
    /// 既有（已上傳）附件，與新選照片並列顯示；計入 `maxCount` 總上限。
    var existingAttachments: [ExistingAttachmentRef] = []
    /// 提供時既有附件顯示移除鈕；移除後可再加新照片。
    var onRemoveExisting: ((ExistingAttachmentRef) -> Void)? = nil
    var onError: ((String) -> Void)? = nil

    @State private var showSourceDialog = false
    @State private var showCamera = false
    @State private var showLibraryPicker = false
    @State private var librarySelection: [PhotosPickerItem] = []
    @State private var previewPhoto: PickedUploadPhoto?
    @State private var isLoadingLibrary = false

    private var remainingSlots: Int {
        max(0, maxCount - existingAttachments.count - photos.count)
    }

    private var canAddMore: Bool {
        !isDisabled && remainingSlots > 0
    }

    private var cameraAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                showSourceDialog = true
            } label: {
                Label(addButtonTitle, systemImage: "camera.fill")
            }
            .disabled(!canAddMore || isLoadingLibrary)

            if isLoadingLibrary {
                ProgressView()
                    .controlSize(.small)
            }

            if !existingAttachments.isEmpty || !photos.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(existingAttachments) { ref in
                            ExistingAttachmentThumbnail(
                                ref: ref,
                                onRemove: (isDisabled || onRemoveExisting == nil) ? nil : { onRemoveExisting?(ref) }
                            )
                        }
                        ForEach(photos) { photo in
                            photoThumbnail(photo)
                        }
                    }
                    // X 移除鈕往上／往右各凸出 6pt，需留邊距避免被 ScrollView 裁切。
                    .padding(EdgeInsets(top: 8, leading: 2, bottom: 4, trailing: 8))
                }
            }

            if let caption, !caption.isEmpty {
                Text(caption)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .confirmationDialog("加入照片", isPresented: $showSourceDialog, titleVisibility: .visible) {
            if cameraAvailable {
                Button("拍照") {
                    showCamera = true
                }
            }
            Button("從相簿選擇") {
                librarySelection = []
                showLibraryPicker = true
            }
            Button("取消", role: .cancel) {}
        }
        .photosPicker(
            isPresented: $showLibraryPicker,
            selection: $librarySelection,
            maxSelectionCount: remainingSlots,
            matching: .images
        )
        .onChange(of: librarySelection) { _, items in
            guard !items.isEmpty else { return }
            Task { await appendFromLibrary(items) }
        }
        .fullScreenCover(isPresented: $showCamera) {
            CameraImagePicker { image in
                appendCameraPhoto(image)
            }
            .ignoresSafeArea()
        }
        .fullScreenCover(item: $previewPhoto) { photo in
            PhotoPreviewScreen(image: photo.image) {
                previewPhoto = nil
            }
        }
    }

    private var addButtonTitle: String {
        let total = existingAttachments.count + photos.count
        if total == 0 {
            return "加入照片"
        }
        return "已選 \(total) 張（最多 \(maxCount) 張）"
    }

    private func photoThumbnail(_ photo: PickedUploadPhoto) -> some View {
        ZStack(alignment: .topTrailing) {
            Button {
                previewPhoto = photo
            } label: {
                Image(uiImage: photo.image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 72, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("預覽照片")

            if !isDisabled {
                Button {
                    removePhoto(photo)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Color.black.opacity(0.55))
                        .font(.body)
                }
                .offset(x: 6, y: -6)
                .accessibilityLabel("移除照片")
            }
        }
    }

    private func removePhoto(_ photo: PickedUploadPhoto) {
        photos.removeAll { $0.id == photo.id }
    }

    private func appendCameraPhoto(_ image: UIImage) {
        guard canAddMore else { return }
        do {
            let picked = try PhotoUploadProcessing.pickedPhoto(from: image, filenamePrefix: filenamePrefix)
            photos.append(picked)
        } catch {
            onError?(error.userFacingMessage)
        }
    }

    private func appendFromLibrary(_ items: [PhotosPickerItem]) async {
        await MainActor.run { isLoadingLibrary = true }
        defer {
            Task { @MainActor in
                isLoadingLibrary = false
                librarySelection = []
            }
        }
        var next = await MainActor.run { photos }
        for item in items {
            guard existingAttachments.count + next.count < maxCount else { break }
            do {
                let picked = try await PhotoUploadProcessing.pickedPhoto(from: item, filenamePrefix: filenamePrefix)
                next.append(picked)
            } catch {
                onError?(error.userFacingMessage)
            }
        }
        await MainActor.run { photos = next }
    }
}

/// 既有附件縮圖：尺寸／X 鈕／預覽與新選照片一致（編輯時與 `photoThumbnail` 並列）。
private struct ExistingAttachmentThumbnail: View {
    let ref: ExistingAttachmentRef
    var onRemove: (() -> Void)? = nil

    @State private var image: UIImage?
    @State private var showPreview = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
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
                    .accessibilityLabel("預覽照片")
                } else {
                    ZStack {
                        Color(.secondarySystemFill)
                        ProgressView()
                            .controlSize(.small)
                    }
                }
            }
            .frame(width: 72, height: 72)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            if let onRemove {
                Button(action: onRemove) {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, Color.black.opacity(0.55))
                        .font(.body)
                }
                .offset(x: 6, y: -6)
                .accessibilityLabel("移除照片")
            }
        }
        .task(id: ref.id) {
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
        let candidates = [ref.thumbnailURL, ref.fullURL].compactMap { $0 }
        for u in candidates {
            if let data = try? await APIClient.shared.fetchBinary(url: u),
               let img = UIImage(data: data) {
                await MainActor.run { image = img }
                return
            }
        }
    }
}

private struct CameraImagePicker: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        picker.allowsEditing = false
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(onImage: onImage, dismiss: dismiss)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onImage: (UIImage) -> Void
        let dismiss: DismissAction

        init(onImage: @escaping (UIImage) -> Void, dismiss: DismissAction) {
            self.onImage = onImage
            self.dismiss = dismiss
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            dismiss()
        }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage {
                onImage(image)
            }
            dismiss()
        }
    }
}

struct PhotoPreviewScreen: View {
    let image: UIImage
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("關閉", action: onClose)
                }
            }
        }
    }
}
