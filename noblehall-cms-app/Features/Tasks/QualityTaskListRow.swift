import SwiftUI

struct QualityTaskListRow: View {
    let task: QualityTaskListItemDto
    var showsDrawingAndStatus: Bool = false
    /// 離線暫存、尚未同步至伺服器的任務。
    var showsPendingUploadIcon: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(task.name ?? "未命名")
                    .font(.headline)
                    .foregroundStyle(.primary)
                if let subtitle = Self.subtitle(for: task) {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                if showsDrawingAndStatus {
                    HStack(spacing: 8) {
                        if let drawing = task.qualityDrawing?.name, !drawing.isEmpty {
                            Text(drawing)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        if let status = task.status {
                            Text(QualityTaskStatusLabels.displayName(for: status))
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.thinMaterial, in: Capsule())
                        }
                    }
                }
            }
            Spacer(minLength: 0)
            if showsPendingUploadIcon {
                Image(systemName: "icloud.and.arrow.up")
                    .symbolRenderingMode(.hierarchical)
                    .font(.body)
                    .foregroundStyle(.orange)
                    .accessibilityLabel("尚未上傳")
            }
        }
    }

    static func subtitle(for task: QualityTaskListItemDto) -> String? {
        if task.id.hasPrefix("pending-") {
            return "尚未上傳至伺服器"
        }
        var parts: [String] = []
        if let executor = task.executor?.displayName ?? task.executor?.name, !executor.isEmpty {
            parts.append(executor)
        }
        if let room = task.room?.name, !room.isEmpty {
            parts.append(room)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
