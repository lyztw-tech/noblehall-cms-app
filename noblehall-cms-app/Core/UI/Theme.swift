import SwiftUI
import UIKit

// MARK: - App Design System

enum AppTheme {
    static let warmBackground = dynamicColor(
        light: UIColor(red: 0.969, green: 0.953, blue: 0.918, alpha: 1),
        dark: UIColor(red: 0.078, green: 0.067, blue: 0.055, alpha: 1)
    )
    static let cardBackground = dynamicColor(
        light: UIColor(red: 1.000, green: 0.988, blue: 0.965, alpha: 1),
        dark: UIColor(red: 0.133, green: 0.114, blue: 0.094, alpha: 1)
    )
    static let ink = dynamicColor(
        light: UIColor(red: 0.157, green: 0.137, blue: 0.122, alpha: 1),
        dark: UIColor(red: 0.957, green: 0.933, blue: 0.886, alpha: 1)
    )
    static let secondaryInk = dynamicColor(
        light: UIColor(red: 0.478, green: 0.443, blue: 0.408, alpha: 1),
        dark: UIColor(red: 0.765, green: 0.714, blue: 0.647, alpha: 1)
    )
    static let brandGold = dynamicColor(
        light: UIColor(red: 0.604, green: 0.478, blue: 0.275, alpha: 1),
        dark: UIColor(red: 0.839, green: 0.694, blue: 0.424, alpha: 1)
    )
    static let softGold = dynamicColor(
        light: UIColor(red: 0.718, green: 0.647, blue: 0.478, alpha: 1),
        dark: UIColor(red: 0.910, green: 0.824, blue: 0.624, alpha: 1)
    )
    static let hairline = dynamicColor(
        light: UIColor(red: 0.886, green: 0.847, blue: 0.765, alpha: 1),
        dark: UIColor(red: 0.298, green: 0.255, blue: 0.204, alpha: 1)
    )
    static let success = dynamicColor(
        light: UIColor(red: 0.282, green: 0.502, blue: 0.376, alpha: 1),
        dark: UIColor(red: 0.443, green: 0.718, blue: 0.565, alpha: 1)
    )
    static let warning = dynamicColor(
        light: UIColor(red: 0.777, green: 0.471, blue: 0.184, alpha: 1),
        dark: UIColor(red: 0.949, green: 0.631, blue: 0.325, alpha: 1)
    )

    static var cardShadow: Color {
        dynamicColor(
            light: UIColor.black.withAlphaComponent(0.06),
            dark: UIColor.black.withAlphaComponent(0.30)
        )
    }

    private static func dynamicColor(light: UIColor, dark: UIColor) -> Color {
        Color(UIColor { traitCollection in
            traitCollection.userInterfaceStyle == .dark ? dark : light
        })
    }
}

enum AppAppearanceMode: String, CaseIterable, Identifiable {
    static let storageKey = "appAppearanceMode"

    case system
    case light
    case dark

    var id: String { rawValue }

    var title: String {
        switch self {
        case .system:
            return "跟隨系統"
        case .light:
            return "淺色"
        case .dark:
            return "深色"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system:
            return nil
        case .light:
            return .light
        case .dark:
            return .dark
        }
    }
}

struct AppScreenBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(AppTheme.warmBackground.ignoresSafeArea())
            .scrollContentBackground(.hidden)
    }
}

struct AppCardStyle: ViewModifier {
    var cornerRadius: CGFloat = 22

    func body(content: Content) -> some View {
        content
            .background(AppTheme.cardBackground, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(AppTheme.hairline.opacity(0.65), lineWidth: 1)
            )
            .shadow(color: AppTheme.cardShadow, radius: 16, x: 0, y: 8)
    }
}

struct AppPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(AppTheme.brandGold.opacity(configuration.isPressed ? 0.82 : 1), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: AppTheme.brandGold.opacity(configuration.isPressed ? 0.10 : 0.24), radius: 10, x: 0, y: 5)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
    }
}

struct AppPlainCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
    }
}

struct AppSectionHeader: View {
    let eyebrow: String
    let title: String
    var subtitle: String? = nil
    var systemImage: String? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppTheme.brandGold)
                    .frame(width: 38, height: 38)
                    .background(AppTheme.brandGold.opacity(0.11), in: Circle())
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(eyebrow.uppercased())
                    .font(.caption.weight(.semibold))
                    .tracking(1.8)
                    .foregroundStyle(AppTheme.brandGold)
                Text(title)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(AppTheme.ink)
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(AppTheme.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

struct AppLaunchSplashView: View {
    @State private var logoVisible = false
    @State private var pulse = false

    var body: some View {
        ZStack {
            AppTheme.warmBackground
                .ignoresSafeArea()

            VStack(spacing: 28) {
                Image("NobleHallLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 190)
                    .scaleEffect(logoVisible ? 1 : 0.92)
                    .opacity(logoVisible ? 1 : 0)
                    .shadow(color: AppTheme.brandGold.opacity(0.14), radius: 18, x: 0, y: 10)

                ZStack {
                    Circle()
                        .stroke(AppTheme.brandGold.opacity(0.16), lineWidth: 3)
                        .frame(width: 34, height: 34)
                    Circle()
                        .trim(from: 0, to: 0.68)
                        .stroke(
                            AppTheme.brandGold,
                            style: StrokeStyle(lineWidth: 3, lineCap: .round)
                        )
                        .frame(width: 34, height: 34)
                        .rotationEffect(.degrees(pulse ? 360 : 0))
                }
                .opacity(logoVisible ? 1 : 0)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.62, dampingFraction: 0.78)) {
                logoVisible = true
            }
            withAnimation(.linear(duration: 1.0).repeatForever(autoreverses: false)) {
                pulse = true
            }
        }
    }
}

struct AppStatusPill: View {
    let title: String
    var systemImage: String? = nil
    var tint: Color = AppTheme.brandGold
    var background: Color? = nil

    var body: some View {
        HStack(spacing: 5) {
            if let systemImage { Image(systemName: systemImage) }
            Text(title)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(tint)
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background((background ?? tint.opacity(0.12)), in: Capsule())
    }
}

/// 列表用的小型離線提示（tag 樣式，不佔整列說明區塊）。
struct AppOfflineTag: View {
    var text: String = "離線模式"
    /// 前段狀態（例：離線中）；與 `detail` 同時設定時優先顯示。
    var prefix: String?
    var detail: String?
    /// 單行長文案：字級略大。
    var singleLine: Bool = false

    private var usesSplitCopy: Bool {
        guard let prefix, let detail else { return false }
        return !prefix.isEmpty && !detail.isEmpty
    }

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "wifi.slash")
            if usesSplitCopy, let prefix, let detail {
                Text(prefix)
                    .fontWeight(.semibold)
                Text(detail)
                    .fontWeight(.medium)
            } else {
                Text(text)
            }
        }
        .font(usesSplitCopy || singleLine ? .caption.weight(.medium) : .caption2.weight(.semibold))
        .foregroundStyle(AppTheme.warning)
        .lineLimit(1)
        .padding(.horizontal, usesSplitCopy || singleLine ? 12 : 8)
        .padding(.vertical, usesSplitCopy || singleLine ? 6 : 4)
        .background(AppTheme.warning.opacity(0.12), in: Capsule())
    }
}

/// 隱藏 NavigationBar 底部分隔線（透明導覽列時常會露出一條 hairline）。
struct AppNavigationBarSeparatorHidden: ViewModifier {
    func body(content: Content) -> some View {
        content.background(AppNavigationBarSeparatorConfigurator())
    }
}

private struct AppNavigationBarSeparatorConfigurator: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController { UIViewController() }

    func updateUIViewController(_ viewController: UIViewController, context: Context) {
        DispatchQueue.main.async {
            guard let navigationBar = viewController.navigationController?.navigationBar else { return }
            let appearance = UINavigationBarAppearance()
            appearance.configureWithTransparentBackground()
            appearance.shadowColor = .clear
            appearance.shadowImage = UIImage()
            appearance.backgroundColor = .clear
            navigationBar.standardAppearance = appearance
            navigationBar.scrollEdgeAppearance = appearance
            navigationBar.compactAppearance = appearance
        }
    }
}

extension View {
    func appScreen() -> some View { modifier(AppScreenBackground()) }
    func appCard(cornerRadius: CGFloat = 22) -> some View { modifier(AppCardStyle(cornerRadius: cornerRadius)) }
    func appNavigationBarSeparatorHidden() -> some View { modifier(AppNavigationBarSeparatorHidden()) }

    /// 設定／篩選等分組列表：暖色底、圓角卡片列。
    func appGroupedListStyle() -> some View {
        listStyle(.insetGrouped)
            .listSectionSpacing(14)
            .listRowBackground(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(AppTheme.cardBackground)
            )
            .appScreen()
    }

    /// Form 頁面（日期、文字輸入等）與列表視覺一致。
    func appFormStyle() -> some View {
        listSectionSpacing(14)
            .listRowBackground(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(AppTheme.cardBackground)
            )
            .appScreen()
    }

    /// 列表內嵌離線 tag 列：透明背景、緊湊間距。
    func appOfflineListTagRow() -> some View {
        listRowInsets(EdgeInsets(top: 2, leading: 20, bottom: 6, trailing: 20))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
    }
}
