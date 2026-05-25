import Foundation
import Observation

private nonisolated enum SessionKeys {
    static let accessToken = "construction.session.accessToken"
    static let refreshToken = "construction.session.refreshToken"
    static let tenantId = "construction.session.tenantId"
    static let projectId = "construction.session.projectId"
}

nonisolated enum AuthTokenStore {
    nonisolated static var accessToken: String? {
        get { UserDefaults.standard.string(forKey: SessionKeys.accessToken) }
        set {
            if let value = newValue, !value.isEmpty {
                UserDefaults.standard.set(value, forKey: SessionKeys.accessToken)
            } else {
                UserDefaults.standard.removeObject(forKey: SessionKeys.accessToken)
            }
        }
    }

    nonisolated static var refreshToken: String? {
        get { UserDefaults.standard.string(forKey: SessionKeys.refreshToken) }
        set {
            if let value = newValue, !value.isEmpty {
                UserDefaults.standard.set(value, forKey: SessionKeys.refreshToken)
            } else {
                UserDefaults.standard.removeObject(forKey: SessionKeys.refreshToken)
            }
        }
    }

    nonisolated static func save(accessToken: String, refreshToken: String) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
    }

    nonisolated static func clear() {
        accessToken = nil
        refreshToken = nil
    }
}

/// 登入狀態、當前租戶、選定專案。Session token 由 `AuthTokenStore` 保存。
@MainActor
@Observable
final class SessionStore {
    private(set) var currentUser: UserDto?
    private(set) var spaceId: String?
    /// 使用者在專案列表選定後進入主畫面。
    private(set) var selectedProjectCode: String?

    var isLoggedIn: Bool { currentUser != nil && AuthTokenStore.accessToken != nil }

    init() {
        spaceId = UserDefaults.standard.string(forKey: SessionKeys.tenantId)
        selectedProjectCode = UserDefaults.standard.string(forKey: SessionKeys.projectId)
    }

    /// App 冷啟動時若 token 仍有效，還原使用者與租戶。
    func restoreSessionIfPossible() async {
        guard currentUser == nil else { return }
        guard AuthTokenStore.accessToken != nil else {
            clearSession()
            return
        }
        do {
            let user = try await AuthAPI.fetchMe()
            currentUser = user
            setSpaceId(user.tenantId)
        } catch {
            do {
                try await AuthAPI.refreshSession()
                let user = try await AuthAPI.fetchMe()
                currentUser = user
                setSpaceId(user.tenantId)
            } catch {
                clearSession()
            }
        }
    }

    func applyLoginResponse(_ response: LoginResponseDto) {
        AuthTokenStore.save(accessToken: response.accessToken, refreshToken: response.refreshToken)
        currentUser = response.user
        setSpaceId(response.user.tenantId)
    }

    func applyUser(_ user: UserDto) {
        currentUser = user
        setSpaceId(user.tenantId)
    }

    func setSpaceId(_ id: String?) {
        spaceId = id
        if let id, !id.isEmpty {
            UserDefaults.standard.set(id, forKey: SessionKeys.tenantId)
        } else {
            UserDefaults.standard.removeObject(forKey: SessionKeys.tenantId)
        }
    }

    func setSelectedProject(code: String?) {
        selectedProjectCode = code
        if let code, !code.isEmpty {
            UserDefaults.standard.set(code, forKey: SessionKeys.projectId)
        } else {
            UserDefaults.standard.removeObject(forKey: SessionKeys.projectId)
        }
    }

    /// 清除記憶體與 token／UserDefaults。若需一併刪除 SwiftData 與離線檔案，請先呼叫 `CacheMaintenance.purgeAllLocalDataAfterLogout`（見設定內「登出」流程）。
    func clearSession() {
        currentUser = nil
        spaceId = nil
        selectedProjectCode = nil
        AuthTokenStore.clear()
        UserDefaults.standard.removeObject(forKey: SessionKeys.tenantId)
        UserDefaults.standard.removeObject(forKey: SessionKeys.projectId)
        HTTPCookieStorage.shared.cookies?.forEach { HTTPCookieStorage.shared.deleteCookie($0) }
    }
}
