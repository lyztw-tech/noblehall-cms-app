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
        Group {
            if trimmedQuery.isEmpty {
                ContentUnavailableView {
                    Label("搜尋任務", systemImage: "magnifyingglass")
                } description: {
                    Text("輸入任務名稱、空間、圖面或執行人")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else if results.isEmpty {
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
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .dismissKeyboardOnScroll()
        .navigationTitle("搜尋")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(
            text: $query,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "任務、空間、圖面、執行人"
        )
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.body.weight(.semibold))
                }
            }
        }
        .dismissKeyboardOnTapOutside()
        .fullScreenCover(item: $selectedRoute) { route in
            TaskDetailView(
                projectCode: projectCode,
                taskId: route.id,
                qualityDrawingIdHint: route.qualityDrawingId,
                onClose: { selectedRoute = nil }
            )
        }
    }

    private struct TaskRoute: Identifiable, Hashable {
        let id: String
        let qualityDrawingId: String?
    }
}
