import SwiftUI

/// 以 sheet 呈現之 iOS 原生搜尋（`searchable(isPresented:)`，搜尋列在鍵盤上方）。
struct NobleHallNativeSearchScreen<Results: View>: View {
    @Binding var query: String
    let prompt: String
    let emptyTitle: String
    let emptyDescription: String
    var emptySystemImage: String = "magnifyingglass"
    let onCancel: () -> Void
    @ViewBuilder let results: () -> Results

    @State private var isSearchFieldPresented = false

    private var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        Group {
            if trimmedQuery.isEmpty {
                ContentUnavailableView {
                    Label(emptyTitle, systemImage: emptySystemImage)
                } description: {
                    Text(emptyDescription)
                        .font(.footnote)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
            } else {
                results()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("搜尋")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $query, isPresented: $isSearchFieldPresented, prompt: prompt)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(action: onCancel) {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                        .font(.title3)
                }
                .accessibilityLabel("關閉搜尋")
            }
        }
        .onAppear {
            isSearchFieldPresented = true
        }
    }
}

extension View {
    /// 任務管理／我的任務：右上角 **篩選（最右）→ 搜尋（其左）**。
    func taskManagementSearchFilterToolbar(
        showSearch: Binding<Bool>,
        showFilter: Binding<Bool>,
        filterActiveCount: Int,
        searchAccessibilityLabel: String
    ) -> some View {
        toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    showFilter.wrappedValue = true
                } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .font(.body.weight(.medium))
                        if filterActiveCount > 0 {
                            Text("\(min(filterActiveCount, 9))")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(4)
                                .background(Color.red, in: Circle())
                                .offset(x: 6, y: -6)
                        }
                    }
                }
                .accessibilityLabel("篩選")

                Button {
                    showSearch.wrappedValue = true
                } label: {
                    Image(systemName: "magnifyingglass")
                }
                .accessibilityLabel(searchAccessibilityLabel)
            }
        }
    }
}
