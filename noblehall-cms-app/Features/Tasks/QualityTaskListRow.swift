import SwiftUI

struct QualityTaskListRow: View {
    let task: QualityTaskListItemDto
    var showsDrawingAndStatus: Bool = true
    var showsPendingUploadIcon: Bool = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(statusTint.opacity(0.12))
                Image(systemName: iconName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(statusTint)
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(task.name ?? "未命名任務")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(NobleHallTheme.ink)
                        .lineLimit(2)
                    if showsPendingUploadIcon {
                        Image(systemName: "icloud.and.arrow.up")
                            .foregroundStyle(NobleHallTheme.warning)
                            .accessibilityLabel("待上傳")
                    }
                }

                if let subtitle = Self.subtitle(for: task, showsPendingUploadIcon: showsPendingUploadIcon) {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(NobleHallTheme.secondaryInk)
                        .lineLimit(2)
                }
                if let created = task.createdAt {
                    HStack(spacing: 5) {
                        Image(systemName: "calendar.badge.clock")
                            .font(.caption2)
                            .foregroundStyle(NobleHallTheme.secondaryInk.opacity(0.7))
                        Text(AppDateTimeFormat.fullDateTime(created))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(NobleHallTheme.secondaryInk.opacity(0.7))
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("建立時間 \(AppDateTimeFormat.fullDateTime(created))")
                }
                if showsDrawingAndStatus {
                    HStack(spacing: 6) {
                        if let drawingName = task.qualityDrawing?.name, !drawingName.isEmpty {
                            NobleHallStatusPill(title: drawingName, systemImage: "doc.text", tint: NobleHallTheme.brandGold)
                        }
                        if let status = task.status, !status.isEmpty {
                            NobleHallStatusPill(title: QualityTaskStatusLabels.displayName(for: status), systemImage: "circle.fill", tint: statusTint)
                        }
                    }
                    .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 8)
        .contentShape(Rectangle())
    }

    private var statusTint: Color {
        let raw = (task.status ?? "").lowercased()
        if raw.contains("review") || raw.contains("審") { return .orange }
        if raw.contains("progress") || raw.contains("執行") || raw.contains("doing") { return NobleHallTheme.brandGold }
        if raw.contains("done") || raw.contains("complete") || raw.contains("完成") { return NobleHallTheme.success }
        if raw.contains("pending") || raw.contains("待") { return NobleHallTheme.warning }
        return NobleHallTheme.softGold
    }

    private var iconName: String {
        showsPendingUploadIcon ? "icloud.and.arrow.up.fill" : "checklist"
    }

    static func subtitle(for task: QualityTaskListItemDto, showsPendingUploadIcon: Bool = false) -> String? {
        if showsPendingUploadIcon { return "已建立，待網路恢復後上傳" }
        var parts: [String] = []
        if let executor = task.executor?.name, !executor.isEmpty { parts.append("執行：\(executor)") }
        if let room = task.room?.name, !room.isEmpty { parts.append(room) }
        if let group = task.group?.name, !group.isEmpty { parts.append(group) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
