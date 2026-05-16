import SwiftData
import SwiftUI

// MARK: - Noble Hall Brand Design System

enum NobleHallTheme {
    static let warmBackground = Color(red: 0.969, green: 0.953, blue: 0.918)
    static let cardBackground = Color(red: 1.000, green: 0.988, blue: 0.965)
    static let ink = Color(red: 0.157, green: 0.137, blue: 0.122)
    static let secondaryInk = Color(red: 0.478, green: 0.443, blue: 0.408)
    static let brandGold = Color(red: 0.604, green: 0.478, blue: 0.275)
    static let softGold = Color(red: 0.718, green: 0.647, blue: 0.478)
    static let hairline = Color(red: 0.886, green: 0.847, blue: 0.765)
    static let success = Color(red: 0.282, green: 0.502, blue: 0.376)
    static let warning = Color(red: 0.777, green: 0.471, blue: 0.184)

    static var cardShadow: Color { Color.black.opacity(0.06) }
}

struct NobleHallScreenBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(NobleHallTheme.warmBackground.ignoresSafeArea())
            .scrollContentBackground(.hidden)
    }
}

struct NobleHallCardStyle: ViewModifier {
    var cornerRadius: CGFloat = 22

    func body(content: Content) -> some View {
        content
            .background(NobleHallTheme.cardBackground, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(NobleHallTheme.hairline.opacity(0.65), lineWidth: 1)
            )
            .shadow(color: NobleHallTheme.cardShadow, radius: 16, x: 0, y: 8)
    }
}

struct NobleHallPrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline.weight(.semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(NobleHallTheme.brandGold.opacity(configuration.isPressed ? 0.82 : 1), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: NobleHallTheme.brandGold.opacity(configuration.isPressed ? 0.10 : 0.24), radius: 10, x: 0, y: 5)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
    }
}

struct NobleHallPlainCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .opacity(configuration.isPressed ? 0.88 : 1)
    }
}

struct NobleHallSectionHeader: View {
    let eyebrow: String
    let title: String
    var subtitle: String? = nil
    var systemImage: String? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(NobleHallTheme.brandGold)
                    .frame(width: 38, height: 38)
                    .background(NobleHallTheme.brandGold.opacity(0.11), in: Circle())
            }
            VStack(alignment: .leading, spacing: 5) {
                Text(eyebrow.uppercased())
                    .font(.caption.weight(.semibold))
                    .tracking(1.8)
                    .foregroundStyle(NobleHallTheme.brandGold)
                Text(title)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(NobleHallTheme.ink)
                if let subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(NobleHallTheme.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
    }
}

struct NobleHallSearchPill: View {
    let title: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: systemImage)
                .foregroundStyle(NobleHallTheme.brandGold)
            Text(title)
                .foregroundStyle(NobleHallTheme.secondaryInk)
            Spacer(minLength: 0)
        }
        .font(.subheadline.weight(.medium))
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(NobleHallTheme.cardBackground, in: Capsule())
        .overlay(Capsule().strokeBorder(NobleHallTheme.hairline.opacity(0.8), lineWidth: 1))
    }
}

struct NobleHallStatusPill: View {
    let title: String
    var systemImage: String? = nil
    var tint: Color = NobleHallTheme.brandGold

    var body: some View {
        HStack(spacing: 5) {
            if let systemImage { Image(systemName: systemImage) }
            Text(title)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(tint)
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(tint.opacity(0.12), in: Capsule())
    }
}

extension View {
    func nobleHallScreen() -> some View { modifier(NobleHallScreenBackground()) }
    func nobleHallCard(cornerRadius: CGFloat = 22) -> some View { modifier(NobleHallCardStyle(cornerRadius: cornerRadius)) }
}

struct AppRootView: View {
    @Environment(SessionStore.self) private var session
    @Environment(NetworkPathMonitor.self) private var network
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        Group {
            if !session.isLoggedIn {
                LoginView()
            } else if session.selectedProjectCode == nil {
                ProjectListView()
            } else if let code = session.selectedProjectCode {
                MainTabView(projectCode: code)
            }
        }
        .tint(NobleHallTheme.brandGold)
        .dismissKeyboardOnTapOutside()
        .animation(.easeInOut(duration: 0.2), value: session.isLoggedIn)
        .animation(.easeInOut(duration: 0.2), value: session.selectedProjectCode)
        .task(id: bootstrapTaskKey) {
            await bootstrapSessionAndPreload()
        }
        .task {
            await NetworkReconnectNotifier.requestAuthorizationIfNotDetermined()
        }
        .onChange(of: network.isConnected) { wasConnected, isConnected in
            Task {
                await NetworkReconnectNotifier.handleTransition(
                    wasConnected: wasConnected,
                    isConnected: isConnected,
                    isLoggedIn: session.isLoggedIn
                )
            }
            if isConnected {
                Task { await bootstrapSessionAndPreload() }
            }
        }
    }

    private var bootstrapTaskKey: String {
        "\(session.isLoggedIn)|\(session.selectedProjectCode ?? "")|\(session.spaceId ?? "")|\(network.isConnected)"
    }

    /// 先還原登入（Cookie），再預載平面圖；避免預載搶跑導致圖檔下載失敗、僅有座標點。
    private func bootstrapSessionAndPreload() async {
        if session.currentUser == nil {
            await session.restoreSessionIfPossible()
            try? await Task.sleep(nanoseconds: 400_000_000)
        }
        guard session.isLoggedIn,
              let projectCode = session.selectedProjectCode,
              let spaceId = session.spaceId,
              network.isConnected
        else { return }

        await OutboxSync.flushPending(modelContext: modelContext, spaceId: spaceId, isOnline: true)
        await PlanAssetCache.preloadAll(
            projectCode: projectCode,
            spaceId: spaceId,
            context: modelContext,
            force: false
        )
        if let stats = try? PlanAssetCache.stats(projectCode: projectCode, context: modelContext),
           stats.drawingCount > 0,
           stats.drawingsWithImageCount < stats.drawingCount,
           network.isConnected {
            try? await Task.sleep(nanoseconds: 800_000_000)
            await PlanAssetCache.preloadAll(
                projectCode: projectCode,
                spaceId: spaceId,
                context: modelContext,
                force: true
            )
        }
    }
}
