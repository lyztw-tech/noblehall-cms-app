import Foundation

enum URLResolver: Sendable {
    /// 將後端回傳的檔案路徑轉成可請求的絕對 URL。
    /// **須與 Web `getFileUrl` 一致**：`VITE_API_BASE_URL`（含 `/api`）+ `/files/...` → `…/api/files/…`。
    /// 若誤用「僅 origin」組 `http://host/files/…`，在只反向代理 `/api` 的環境會 404，平面圖永遠載不到。
    static func absoluteAssetURL(_ pathOrURL: String?, apiRoot: URL = AppConfiguration.apiRootURL) -> URL? {
        guard let raw = pathOrURL?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
        if raw.hasPrefix("http://") || raw.hasPrefix("https://") {
            return URL(string: raw)
        }
        var path = raw.hasPrefix("/") ? raw : "/" + raw
        path = path.replacingOccurrences(of: "//", with: "/")
        if !path.hasPrefix("/") { path = "/" + path }

        var base = apiRoot.absoluteString
        while base.hasSuffix("/") { base.removeLast() }
        return URL(string: base + path)
    }
}
