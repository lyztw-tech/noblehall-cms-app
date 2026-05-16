import Foundation

/// App 內共用的日期／時間字串（`en_US_POSIX`、公曆、裝置目前時區）。
enum AppDateTimeFormat {
    private static let fullDateTimeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy/MM/dd HH:mm:ss"
        return f
    }()

    private static let yearMonthDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy/MM/dd"
        return f
    }()

    /// `yyyy/MM/dd HH:mm:ss`（24 小時制）。
    static func fullDateTime(_ date: Date) -> String {
        fullDateTimeFormatter.string(from: date)
    }

    /// `yyyy/MM/dd`（不含時分秒）。
    static func yearMonthDay(_ date: Date) -> String {
        yearMonthDayFormatter.string(from: date)
    }
}
