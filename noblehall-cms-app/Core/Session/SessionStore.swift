import Foundation
import Observation

private enum SessionKeys {
    static let spaceId = "nh.session.spaceId"
    static let projectCode = "nh.session.projectCode"
}

/// 登入狀態、當前 Space、選定專案。Session 本體由 **Cookie** 保存於 `HTTPCookieStorage.shared`。
@MainActor
@Observable
final class SessionStore {
    private(set) var currentUser: UserDto?
    private(set) var spaceId: String?
    /// 使用者在專案列表選定後進入主畫面。
    private(set) var selectedProjectCode: String?

    var isLoggedIn: Bool { currentUser != nil }

    init() {
        spaceId = UserDefaults.standard.string(forKey: SessionKeys.spaceId)
        selectedProjectCode = UserDefaults.standard.string(forKey: SessionKeys.projectCode)
    }

    /// App 冷啟動時若 Cookie 仍有效，還原使用者與 Space。
    func restoreSessionIfPossible() async {
        guard currentUser == nil else { return }
        do {
            if let sid = spaceId, !sid.isEmpty {
                currentUser = try await AuthAPI.fetchMe(spaceId: sid)
            } else {
                let u = try await AuthAPI.fetchMe(spaceId: nil)
                if let first = u.spaceIds?.first {
                    setSpaceId(first)
                    currentUser = try await AuthAPI.fetchMe(spaceId: first)
                } else {
                    currentUser = u
                    if let sid = u.spaceId, !sid.isEmpty { setSpaceId(sid) }
                }
            }
        } catch {
            clearSession()
        }
    }

    func applyLoginResponse(_ user: UserDto) {
        currentUser = user
        if let sid = user.spaceId, !sid.isEmpty {
            setSpaceId(sid)
        }
    }

    func setSpaceId(_ id: String?) {
        spaceId = id
        if let id, !id.isEmpty {
            UserDefaults.standard.set(id, forKey: SessionKeys.spaceId)
        } else {
            UserDefaults.standard.removeObject(forKey: SessionKeys.spaceId)
        }
    }

    func setSelectedProject(code: String?) {
        selectedProjectCode = code
        if let code, !code.isEmpty {
            UserDefaults.standard.set(code, forKey: SessionKeys.projectCode)
        } else {
            UserDefaults.standard.removeObject(forKey: SessionKeys.projectCode)
        }
    }

    /// 清除記憶體與 Cookie／UserDefaults。若需一併刪除 SwiftData 與離線檔案，請先呼叫 `CacheMaintenance.purgeAllLocalDataAfterLogout`（見設定內「登出」流程）。
    func clearSession() {
        currentUser = nil
        spaceId = nil
        selectedProjectCode = nil
        UserDefaults.standard.removeObject(forKey: SessionKeys.spaceId)
        UserDefaults.standard.removeObject(forKey: SessionKeys.projectCode)
        HTTPCookieStorage.shared.cookies?.forEach { HTTPCookieStorage.shared.deleteCookie($0) }
    }
}
