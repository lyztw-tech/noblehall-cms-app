import Foundation

enum QualityDrawingSearch {
    static func filter(_ drawings: [QualityDrawingListItemDto], query: String) -> [QualityDrawingListItemDto] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return [] }
        return drawings
            .filter { $0.drawing.name.lowercased().contains(q) }
            .sorted { $0.drawing.name < $1.drawing.name }
    }
}
