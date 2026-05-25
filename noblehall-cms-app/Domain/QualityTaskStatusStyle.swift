import SwiftUI

/// 與 Web `QUALITY_TASK_STATUS_CONFIG` 對齊的狀態標籤色。
enum QualityTaskStatusStyle {
    struct Colors {
        let foreground: Color
        let background: Color
    }

    static func colors(for rawStatus: String?) -> Colors {
        switch normalize(rawStatus) {
        case "pending_assignment":
            return Colors(
                foreground: Color(red: 0.42, green: 0.45, blue: 0.50),
                background: Color(red: 0.95, green: 0.96, blue: 0.97)
            )
        case "in_progress":
            return Colors(
                foreground: Color(red: 0.08, green: 0.28, blue: 0.90),
                background: Color(red: 0.94, green: 0.96, blue: 1.00)
            )
        case "director_check":
            return Colors(
                foreground: Color(red: 0.49, green: 0.23, blue: 0.93),
                background: Color(red: 0.95, green: 0.91, blue: 1.00)
            )
        case "in_review":
            return Colors(
                foreground: Color(red: 0.82, green: 0.53, blue: 0.00),
                background: Color(red: 1.00, green: 0.98, blue: 0.92)
            )
        case "rejected":
            return Colors(
                foreground: Color(red: 0.83, green: 0.20, blue: 0.20),
                background: Color(red: 1.00, green: 0.89, blue: 0.89)
            )
        case "approved":
            return Colors(
                foreground: Color(red: 0.13, green: 0.55, blue: 0.13),
                background: Color(red: 0.94, green: 0.99, blue: 0.95)
            )
        case "info":
            return Colors(
                foreground: Color(red: 0.42, green: 0.45, blue: 0.50),
                background: Color(red: 0.98, green: 0.98, blue: 0.99)
            )
        default:
            return Colors(
                foreground: NobleHallTheme.brandGold,
                background: NobleHallTheme.brandGold.opacity(0.12)
            )
        }
    }

    private static func normalize(_ raw: String?) -> String {
        QualityTaskEditEligibility.normalizedStatus(raw)
    }
}
