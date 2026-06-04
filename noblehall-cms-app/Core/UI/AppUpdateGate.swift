import SwiftUI
import UIKit

@MainActor
@Observable
final class AppUpdateGate {
    var requiredUpdate: RequiredAppUpdate?

    private var isChecking = false

    func checkForRequiredUpdate() async {
        guard !isChecking else { return }
        isChecking = true
        defer { isChecking = false }

        do {
            let versionInfo = try await AppVersionAPI.fetchVersionInfo()
            guard versionInfo.forceUpdate == true,
                  VersionComparator.compare(AppMetadata.version, versionInfo.minimumVersion) == .orderedAscending else {
                requiredUpdate = nil
                return
            }
            requiredUpdate = RequiredAppUpdate(
                currentVersion: AppMetadata.version,
                minimumVersion: versionInfo.minimumVersion,
                latestVersion: versionInfo.latestVersion,
                appStoreURL: URL(string: versionInfo.appStoreURL),
                message: versionInfo.message,
                releaseNotes: versionInfo.releaseNotes
            )
        } catch {
            print("[AppUpdateGate] version check failed: \(error.localizedDescription)")
        }
    }

    func openAppStore() {
        guard let url = requiredUpdate?.appStoreURL else { return }
        UIApplication.shared.open(url)
    }
}

struct RequiredAppUpdate: Identifiable, Equatable {
    let id = "required-app-update"
    let currentVersion: String
    let minimumVersion: String
    let latestVersion: String
    let appStoreURL: URL?
    let message: String?
    let releaseNotes: String?
}

private enum VersionComparator {
    static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = versionComponents(lhs)
        let right = versionComponents(rhs)
        let count = max(left.count, right.count)

        for index in 0 ..< count {
            let leftValue = index < left.count ? left[index] : 0
            let rightValue = index < right.count ? right[index] : 0
            if leftValue < rightValue { return .orderedAscending }
            if leftValue > rightValue { return .orderedDescending }
        }

        return .orderedSame
    }

    private static func versionComponents(_ version: String) -> [Int] {
        version
            .split(separator: ".")
            .map { part in
                let numericPrefix = part.prefix { $0.isNumber }
                return Int(numericPrefix) ?? 0
            }
    }
}

struct RequiredAppUpdateView: View {
    let update: RequiredAppUpdate
    let onOpenAppStore: () -> Void

    var body: some View {
        ZStack {
            NobleHallTheme.warmBackground
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Image(systemName: "arrow.down.app.fill")
                    .font(.system(size: 54, weight: .semibold))
                    .foregroundStyle(NobleHallTheme.brandGold)

                VStack(spacing: 10) {
                    Text("需要更新 App")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(NobleHallTheme.ink)

                    Text(update.message ?? "目前版本 \(update.currentVersion) 已不再支援。請更新至最新版本後繼續使用。")
                        .font(.body)
                        .foregroundStyle(NobleHallTheme.secondaryInk)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(spacing: 6) {
                    Text("最低支援版本：\(update.minimumVersion)")
                    Text("最新版本：\(update.latestVersion)")
                }
                .font(.footnote.weight(.medium))
                .foregroundStyle(NobleHallTheme.secondaryInk)

                if let releaseNotes = update.releaseNotes, !releaseNotes.isEmpty {
                    Text(releaseNotes)
                        .font(.footnote)
                        .foregroundStyle(NobleHallTheme.secondaryInk)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(NobleHallTheme.brandGold.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                Button(action: onOpenAppStore) {
                    Text("前往 App Store 更新")
                }
                .buttonStyle(NobleHallPrimaryButtonStyle())
                .disabled(update.appStoreURL == nil)
            }
            .padding(28)
            .frame(maxWidth: 420)
            .nobleHallCard(cornerRadius: 28)
            .padding(24)
        }
    }
}
