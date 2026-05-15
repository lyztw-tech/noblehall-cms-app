//
//  AppConfiguration.swift
//  noblehall-cms-app
//
//  與 constructionApp 的 `AppConfiguration` 相同策略：環境變數優先、Debug 本機／區網 http、Release 強制 https。
//  Noblehall CMS 後端 API root 為 **`/api`**（對齊 Web `VITE_API_BASE_URL` + `/api` 路由）。
//

import Foundation

/// API root（含路徑 **`/api`**），所有 `APIClient` 請求皆相對於此。
enum AppConfiguration: Sendable {
    /// Release／TestFlight／App Store 預設；正式上架前請改為實際正式網址。
    private nonisolated static let productionAPIRootURLString = "https://api.example.com/api"

    /// DEBUG 預設本機；實機請改此常數，或於 Xcode Scheme 設定 `API_BASE_URL`（建議區網 IP）。
    private nonisolated static let debugDefaultAPIRootURLString = "http://192.168.0.71:3000/api"

    /// 1. 環境變數 `API_BASE_URL`（完整 root，須含 `/api`）  
    /// 2. DEBUG 且 `FORCE_PRODUCTION_API=1` → 使用 Release 預設字串  
    /// 3. 否則依 `#if DEBUG` 選 Debug／Release 預設
    nonisolated static var apiRootURL: URL {
        if let raw = ProcessInfo.processInfo.environment["API_BASE_URL"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !raw.isEmpty,
           let url = URL(string: raw)
        {
            return url
        }
        #if DEBUG
        if ProcessInfo.processInfo.environment["FORCE_PRODUCTION_API"] == "1" {
            return URL(string: productionAPIRootURLString)!
        }
        return URL(string: debugDefaultAPIRootURLString)!
        #else
        return URL(string: productionAPIRootURLString)!
        #endif
    }

    /// 不含 path 的 origin（例 `http://127.0.0.1:3000`），用於組 `/api/files/...` 等絕對 URL。
    nonisolated static var serverOriginURL: URL {
        apiRootURL.deletingLastPathComponent()
    }

    /// 將後端回傳的相對路徑（如 `/api/files/...`）轉成絕對 URL。
    nonisolated static func absoluteURL(apiPath: String) -> URL? {
        let path = apiPath.hasPrefix("/") ? apiPath : "/" + apiPath
        return URL(string: path, relativeTo: serverOriginURL)?.absoluteURL
    }

    /// 登入頁等 developer-facing 一行說明（含編譯模式與目前 API root）。
    nonisolated static var developerFacingAPIStatusLine: String {
        let u = apiRootURL
        let authority: String = {
            guard let h = u.host else { return "" }
            if let p = u.port { return "\(h):\(p)" }
            return h
        }()
        #if DEBUG
        let mode = ProcessInfo.processInfo.environment["FORCE_PRODUCTION_API"] == "1" ? "Debug→正式預設" : "Debug"
        #else
        let mode = "Release"
        #endif
        let path = u.path.isEmpty ? "" : u.path
        return "\(mode) · \(u.scheme ?? "?")://\(authority)\(path)"
    }

    private nonisolated static func isLocalhostAPIHost(_ url: URL) -> Bool {
        guard let host = url.host?.lowercased() else { return false }
        return host == "localhost" || host == "127.0.0.1" || host == "::1" || host == "[::1]"
    }

    private nonisolated static func isPrivateIPv4LANHost(_ url: URL) -> Bool {
        guard let host = url.host else { return false }
        let octets = host.split(separator: ".")
        guard octets.count == 4,
              let a = Int(octets[0]), let b = Int(octets[1]),
              let c = Int(octets[2]), let d = Int(octets[3]),
              (0 ... 255).contains(a), (0 ... 255).contains(b),
              (0 ... 255).contains(c), (0 ... 255).contains(d) else {
            return false
        }
        if a == 10 { return true }
        if a == 172, (16 ... 31).contains(b) { return true }
        if a == 192, b == 168 { return true }
        return false
    }

    /// 發出 API 前呼叫：Release 僅允許 https；DEBUG 允許本機或 RFC1918 區網 http。
    nonisolated static func validateAPIBaseIsSecureForRequests() throws {
        let url = apiRootURL
        if url.scheme?.lowercased() == "https" { return }
        #if DEBUG
        if isLocalhostAPIHost(url) || isPrivateIPv4LANHost(url) { return }
        #endif
        throw APIRequestError.apiMustUseHTTPS
    }
}

// MARK: - App 版本（不依賴 MainActor 上的 Bundle.main）

private final class AppBundleAnchor: NSObject {}

enum AppMetadata: Sendable {
    nonisolated static var version: String {
        (Bundle(for: AppBundleAnchor.self).object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "1.0"
    }
}
