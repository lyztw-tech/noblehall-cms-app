import SwiftUI

struct TaskSearchView: View {
    let projectCode: String
    let tasks: [QualityTaskListItemDto]

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var selectedRoute: TaskRoute?

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var results: [QualityTaskListItemDto] {
        QualityTaskSearch.filter(tasks, query: query)
    }

    var body: some View {
        NavigationStack {
            NobleHallNativeSearchScreen(
                query: $query,
                prompt: "任務、空間、圖面、執行人",
                emptyTitle: "搜尋任務",
                emptyDescription: "輸入任務名稱、空間、平面圖或執行人",
                onCancel: closeSearch
            ) {
                if results.isEmpty {
                    ContentUnavailableView("找不到符合的任務", systemImage: "magnifyingglass")
                } else {
                    List {
                        ForEach(results) { task in
                            Button {
                                guard !task.id.hasPrefix("pending-") else { return }
                                selectedRoute = TaskRoute(id: task.id, qualityDrawingId: task.qualityDrawing?.id)
                            } label: {
                                QualityTaskListRow(
                                    task: task,
                                    showsDrawingAndStatus: true,
                                    showsPendingUploadIcon: task.id.hasPrefix("pending-")
                                )
                            }
                            .disabled(task.id.hasPrefix("pending-"))
                        }
                    }
                    .listStyle(.plain)
                    .dismissKeyboardOnScroll()
                }
            }
        }
        .fullScreenCover(item: $selectedRoute) { route in
            TaskDetailView(
                projectCode: projectCode,
                taskId: route.id,
                qualityDrawingIdHint: route.qualityDrawingId,
                onClose: { selectedRoute = nil }
            )
        }
    }

    private func closeSearch() {
        query = ""
        dismiss()
    }

    private struct TaskRoute: Identifiable, Hashable {
        let id: String
        let qualityDrawingId: String?
    }
}
