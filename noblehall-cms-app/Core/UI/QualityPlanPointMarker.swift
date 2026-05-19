import SwiftUI

/// 平面圖座標標記：有任務數顯示數字圓圈；無任務數顯示小圓點（與 Web PointMarker 一致，不用圖釘）。
enum QualityPlanPointMarker {
    static func badge(count: Int, incomplete: Bool, selected: Bool) -> some View {
        Group {
            if count > 0 {
                numberedBadge(count: count, incomplete: incomplete, selected: selected)
            } else {
                dotBadge(incomplete: incomplete, selected: selected)
            }
        }
    }

    private static func numberedBadge(count: Int, incomplete: Bool, selected: Bool) -> some View {
        let border = incomplete ? Color.red : Color.green
        return ZStack {
            Circle()
                .fill(.white)
                .frame(width: 34, height: 34)
                .overlay(Circle().stroke(border, lineWidth: selected ? 4 : 3))
                .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
            Text("\(count)")
                .font(.caption.weight(.bold))
                .foregroundStyle(incomplete ? .red : .green)
        }
    }

    private static func dotBadge(incomplete: Bool, selected: Bool) -> some View {
        let fill = incomplete ? Color.red : Color(red: 0.30, green: 0.69, blue: 0.31)
        return Circle()
            .fill(fill)
            .frame(width: 10, height: 10)
            .overlay(
                Circle()
                    .strokeBorder(.white, lineWidth: selected ? 2.5 : 2)
            )
            .shadow(color: .black.opacity(0.22), radius: 1.5, y: 1)
    }
}
