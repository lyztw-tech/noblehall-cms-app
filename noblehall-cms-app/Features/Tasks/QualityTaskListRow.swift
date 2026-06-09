import SwiftUI

struct QualityTaskListRow: View {
    let task: QualityTaskListItemDto
    var showsDrawingAndStatus: Bool = true
    var showsPendingUploadIcon: Bool = false
    /// 「指派給我」時隱藏執行人；「全部」時顯示。
    var showsExecutor: Bool = true

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
                        .foregroundStyle(AppTheme.ink)
                        .lineLimit(2)
                    if showsPendingUploadIcon {
                        Image(systemName: "icloud.and.arrow.up")
                            .foregroundStyle(AppTheme.warning)
                            .accessibilityLabel("待上傳")
                    }
                }

                if let subtitle = Self.subtitle(for: task, showsPendingUploadIcon: showsPendingUploadIcon, showsExecutor: showsExecutor) {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.secondaryInk)
                        .lineLimit(2)
                }
                if let created = task.createdAt {
                    HStack(spacing: 5) {
                        Image(systemName: "calendar.badge.clock")
                            .font(.caption2)
                            .foregroundStyle(AppTheme.secondaryInk.opacity(0.7))
                        Text(AppDateTimeFormat.fullDateTime(created))
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(AppTheme.secondaryInk.opacity(0.7))
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("建立時間 \(AppDateTimeFormat.fullDateTime(created))")
                }
                if showsDrawingAndStatus {
                    HStack(spacing: 6) {
                        if let drawingName = task.qualityDrawing?.name, !drawingName.isEmpty {
                            AppStatusPill(title: drawingName, systemImage: "doc.text", tint: AppTheme.brandGold)
                        }
                        if let status = task.status, !status.isEmpty {
                            let style = QualityTaskStatusStyle.colors(for: status)
                            AppStatusPill(
                                title: QualityTaskStatusLabels.displayName(for: status),
                                systemImage: "circle.fill",
                                tint: style.foreground,
                                background: style.background
                            )
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
        QualityTaskStatusStyle.colors(for: task.status).foreground
    }

    private var iconName: String {
        showsPendingUploadIcon ? "icloud.and.arrow.up.fill" : "checklist"
    }

    static func subtitle(
        for task: QualityTaskListItemDto,
        showsPendingUploadIcon: Bool = false,
        showsExecutor: Bool = true
    ) -> String? {
        if showsPendingUploadIcon { return "已建立，待網路恢復後上傳" }
        var parts: [String] = []
        if showsExecutor, let executor = task.executor?.name, !executor.isEmpty {
            parts.append("執行：\(executor)")
        }
        if let group = task.group?.name, !group.isEmpty { parts.append(group) }
        if let room = task.room?.name, !room.isEmpty { parts.append(room) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}
