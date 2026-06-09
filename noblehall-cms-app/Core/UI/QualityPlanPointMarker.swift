import SwiftUI

/// 平面圖座標標記：空間點顯示任務數／小圓點；縮小後的群組點顯示群組名稱。
enum QualityPlanPointMarker {
    private static let webPointBlue = Color(red: 37 / 255, green: 99 / 255, blue: 235 / 255)

    static func badge(count: Int, incomplete: Bool, selected: Bool) -> some View {
        Group {
            if count > 0 {
                numberedBadge(count: count, incomplete: incomplete, selected: selected)
            } else {
                dotBadge(incomplete: incomplete, selected: selected)
            }
        }
    }

    static func clusterBadge(label: String, incomplete: Bool, selected: Bool) -> some View {
        return Text(label)
            .font(.caption.weight(.bold))
            .lineLimit(1)
        .foregroundStyle(.white)
        .padding(.horizontal, selected ? 12 : 10)
        .padding(.vertical, selected ? 9 : 8)
        .background(webPointBlue, in: Capsule())
        .overlay(Capsule().strokeBorder(.white, lineWidth: selected ? 3 : 2))
        .shadow(color: .black.opacity(0.24), radius: selected ? 6 : 3, y: 2)
    }

    private static func numberedBadge(count: Int, incomplete: Bool, selected: Bool) -> some View {
        return ZStack {
            Circle()
                .fill(.white)
                .frame(width: selected ? 48 : 44, height: selected ? 48 : 44)
                .overlay(Circle().stroke(webPointBlue, lineWidth: selected ? 5 : 4))
                .shadow(color: .black.opacity(0.22), radius: 3, y: 1)
            Text("\(count)")
                .font(.subheadline.weight(.bold))
                .foregroundStyle(webPointBlue)
        }
    }

    private static func dotBadge(incomplete: Bool, selected: Bool) -> some View {
        return Circle()
            .fill(webPointBlue)
            .frame(width: selected ? 20 : 16, height: selected ? 20 : 16)
            .overlay(
                Circle()
                    .strokeBorder(.white, lineWidth: selected ? 3.5 : 3)
            )
            .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
    }
}
