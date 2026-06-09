import Foundation
import Observation

private nonisolated enum SessionKeys {
    static let accessToken = "construction.session.accessToken"
    static let refreshToken = "construction.session.refreshToken"
    static let projectId = "construction.session.projectId"
    static let projectName = "construction.session.projectName"
}

nonisolated enum AuthTokenStore {
    nonisolated static var accessToken: String? {
        get { read(SessionKeys.accessToken) }
        set { KeychainStore.set(newValue, for: SessionKeys.accessToken) }
    }

    nonisolated static var refreshToken: String? {
        get { read(SessionKeys.refreshToken) }
        set { KeychainStore.set(newValue, for: SessionKeys.refreshToken) }
    }

    nonisolated static func save(accessToken: String, refreshToken: String) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
    }

    nonisolated static func clear() {
        KeychainStore.delete(SessionKeys.accessToken)
        KeychainStore.delete(SessionKeys.refreshToken)
        // 一併清除任何殘留的舊版 UserDefaults token
        UserDefaults.standard.removeObject(forKey: SessionKeys.accessToken)
        UserDefaults.standard.removeObject(forKey: SessionKeys.refreshToken)
    }

    /// 讀取 token：優先 Keychain；若 Keychain 無值但舊版 UserDefaults 仍有，
    /// 一次性遷移進 Keychain 並清除舊值，避免升級後既有登入者被登出。
    nonisolated private static func read(_ key: String) -> String? {
        if let value = KeychainStore.get(key) { return value }
        if let legacy = UserDefaults.standard.string(forKey: key), !legacy.isEmpty {
            KeychainStore.set(legacy, for: key)
            UserDefaults.standard.removeObject(forKey: key)
            return legacy
        }
        return nil
    }
}

/// 登入狀態與選定專案。Session token 由 `AuthTokenStore`（Keychain）保存。
@MainActor
@Observable
final class SessionStore {
    private(set) var currentUser: UserDto?
    /// 使用者在專案列表選定後進入主畫面。
    private(set) var selectedProjectCode: String?
    /// 選定專案的顯示名稱（給設定頁等 UI 顯示，避免顯示 code/id）。
    private(set) var selectedProjectName: String?

    var isLoggedIn: Bool { currentUser != nil && AuthTokenStore.accessToken != nil }

    init() {
        selectedProjectCode = UserDefaults.standard.string(forKey: SessionKeys.projectId)
        selectedProjectName = UserDefaults.standard.string(forKey: SessionKeys.projectName)
    }

    /// App 冷啟動時若 token 仍有效，還原使用者。
    func restoreSessionIfPossible() async {
        guard currentUser == nil else { return }
        guard AuthTokenStore.accessToken != nil else {
            clearSession()
            return
        }
        do {
            let user = try await AuthAPI.fetchMe()
            currentUser = user
        } catch {
            do {
                try await AuthAPI.refreshSession()
                let user = try await AuthAPI.fetchMe()
                currentUser = user
            } catch {
                clearSession()
            }
        }
    }

    func applyLoginResponse(_ response: LoginResponseDto) {
        AuthTokenStore.save(accessToken: response.accessToken, refreshToken: response.refreshToken)
        currentUser = response.user
    }

    func applyUser(_ user: UserDto) {
        currentUser = user
    }

    func setSelectedProject(code: String?, name: String? = nil) {
        selectedProjectCode = code
        selectedProjectName = name
        if let code, !code.isEmpty {
            UserDefaults.standard.set(code, forKey: SessionKeys.projectId)
        } else {
            UserDefaults.standard.removeObject(forKey: SessionKeys.projectId)
        }
        if let name, !name.isEmpty {
            UserDefaults.standard.set(name, forKey: SessionKeys.projectName)
        } else {
            UserDefaults.standard.removeObject(forKey: SessionKeys.projectName)
        }
    }

    /// 清除記憶體與 token／UserDefaults。若需一併刪除 SwiftData 與離線檔案，請先呼叫 `CacheMaintenance.purgeAllLocalDataAfterLogout`（見設定內「登出」流程）。
    func clearSession() {
        currentUser = nil
        selectedProjectCode = nil
        selectedProjectName = nil
        AuthTokenStore.clear()
        UserDefaults.standard.removeObject(forKey: SessionKeys.projectId)
        UserDefaults.standard.removeObject(forKey: SessionKeys.projectName)
        HTTPCookieStorage.shared.cookies?.forEach { HTTPCookieStorage.shared.deleteCookie($0) }
    }
}
