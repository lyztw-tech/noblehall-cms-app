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
    /// DEBUG fallback；主要環境請從 Xcode `.xcconfig` 的 `API_BASE_URL` 注入。
    private nonisolated static let debugDefaultAPIRootURLString = "http://192.168.0.71:3000/api"

    /// Release fallback；正式上架前請改為實際正式網址，或使用 Production.xcconfig 注入。
    private nonisolated static let productionAPIRootURLString = "https://api.example.com/api"

    /// 1. Scheme 環境變數 `API_BASE_URL`（方便臨時覆蓋）
    /// 2. Info.plist `API_BASE_URL`（由 `.xcconfig` 注入，正式管理方式）
    /// 3. 依 Debug／Release fallback
    nonisolated static var apiRootURL: URL {
        if let raw = ProcessInfo.processInfo.environment["API_BASE_URL"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !raw.isEmpty,
           let url = URL(string: raw)
        {
            return url
        }
        if let raw = bundledString(forInfoKey: "API_BASE_URL"),
           let url = URL(string: raw)
        {
            return url
        }
        #if DEBUG
        return URL(string: debugDefaultAPIRootURLString)!
        #else
        return URL(string: productionAPIRootURLString)!
        #endif
    }

    /// 目前 build 環境名稱（由 `.xcconfig` 注入）。
    nonisolated static var environmentName: String {
        bundledString(forInfoKey: "NOBLEHALL_ENVIRONMENT") ?? {
            #if DEBUG
            return "Debug"
            #else
            return "Release"
            #endif
        }()
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
        let path = u.path.isEmpty ? "" : u.path
        return "\(environmentName) · \(u.scheme ?? "?")://\(authority)\(path)"
    }

    private nonisolated static func bundledString(forInfoKey key: String) -> String? {
        guard let raw = Bundle(for: AppBundleAnchor.self).object(forInfoDictionaryKey: key) as? String else {
            return nil
        }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.hasPrefix("$(") else { return nil }
        return trimmed
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
