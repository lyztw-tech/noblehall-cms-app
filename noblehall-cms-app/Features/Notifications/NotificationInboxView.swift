import SwiftUI

struct NotificationInboxView: View {
    @Environment(NotificationInboxStore.self) private var inbox
    @Environment(\.dismiss) private var dismiss

    var showsCloseButton: Bool = true
    var onOpenDeepLink: (NotificationDeepLink) -> Void

    var body: some View {
        NavigationStack {
            Group {
                if inbox.isLoading, inbox.items.isEmpty {
                    ProgressView("載入通知…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let err = inbox.loadError, inbox.items.isEmpty {
                    ContentUnavailableView("無法載入", systemImage: "exclamationmark.triangle", description: Text(err))
                } else if inbox.items.isEmpty {
                    ContentUnavailableView("沒有通知", systemImage: "tray", description: Text("任務指派與審核更新會顯示在這裡"))
                } else {
                    List {
                        ForEach(inbox.items) { item in
                            Button {
                                if let link = inbox.handleTap(item) {
                                    if showsCloseButton { dismiss() }
                                    onOpenDeepLink(link)
                                }
                            } label: {
                                NotificationInboxRow(item: item)
                            }
                            .buttonStyle(.plain)
                            .onAppear {
                                if item.id == inbox.items.last?.id {
                                    Task { await inbox.loadMoreIfNeeded() }
                                }
                            }
                        }
                        if inbox.isLoadingMore {
                            HStack {
                                Spacer()
                                ProgressView()
                                Spacer()
                            }
                            .listRowBackground(Color.clear)
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .nobleHallGroupedListStyle()
            .navigationTitle("通知")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if showsCloseButton {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("關閉") { dismiss() }
                            .foregroundStyle(NobleHallTheme.secondaryInk)
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if inbox.unreadCount > 0 {
                        Button("全部已讀") {
                            Task { await inbox.markAllRead() }
                        }
                        .fontWeight(.semibold)
                        .foregroundStyle(NobleHallTheme.brandGold)
                    }
                }
            }
            .refreshable {
                await inbox.fetchInbox(reset: true)
            }
            .task {
                await inbox.fetchInbox(reset: true)
            }
        }
    }
}

private struct NotificationInboxRow: View {
    let item: NotificationDto

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(item.isUnread ? NobleHallTheme.brandGold : NobleHallTheme.hairline.opacity(0.5))
                .frame(width: 8, height: 8)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.subheadline.weight(item.isUnread ? .semibold : .regular))
                    .foregroundStyle(NobleHallTheme.ink)
                    .multilineTextAlignment(.leading)
                if let body = item.body, !body.isEmpty {
                    Text(body)
                        .font(.footnote)
                        .foregroundStyle(NobleHallTheme.secondaryInk)
                        .lineLimit(2)
                }
                HStack(spacing: 6) {
                    if let code = item.projectCode, !code.isEmpty {
                        Text(code)
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(NobleHallTheme.brandGold)
                    }
                    Text(AppDateTimeFormat.fullDateTime(item.createdAt))
                        .font(.caption2)
                        .foregroundStyle(NobleHallTheme.secondaryInk)
                }
            }
            Spacer(minLength: 0)
            if item.link != nil {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(NobleHallTheme.secondaryInk)
            }
        }
        .padding(.vertical, 4)
    }
}
