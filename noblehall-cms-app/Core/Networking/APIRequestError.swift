import Foundation

enum APIRequestError: Error, LocalizedError, Sendable {
    case invalidURL
    /// Release 或非法 http；與 constructionApp `AppConfiguration.validateAPIBaseIsSecureForRequests` 一致。
    case apiMustUseHTTPS
    case invalidResponse
    case httpStatus(code: Int, body: String?)
    case decoding(Error)
    /// `attemptedURL` 方便除錯（實機勿用 127.0.0.1）。
    case transport(Error, attemptedURL: URL?)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "無效的網址"
        case .apiMustUseHTTPS:
            return "API 必須使用 HTTPS（Release 不允許非安全連線；Debug 僅允許本機或區網 http）"
        case .invalidResponse:
            return "伺服器回應異常"
        case let .httpStatus(code, body):
            if let body, !body.isEmpty { return "HTTP \(code)：\(body)" }
            return "HTTP \(code)"
        case let .decoding(err):
            return "資料解析失敗：\(err.localizedDescription)"
        case let .transport(err, attemptedURL):
            return Self.transportMessage(error: err, attemptedURL: attemptedURL)
        }
    }

    private static func transportMessage(error: Error, attemptedURL: URL?) -> String {
        let base = (error as NSError).localizedDescription
        let urlNote = attemptedURL.map { " 嘗試：\($0.absoluteString)" } ?? ""

        if let urlErr = error as? URLError {
            switch urlErr.code {
            case .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed:
                return "無法連到伺服器。\(base)\(urlNote)\n\n常見原因：① 後端未啟動或埠錯誤 ② 實機請勿用 127.0.0.1／localhost，請在 Xcode Scheme 設定 API_BASE_URL 與 Web 相同（例如 http://192.168.x.x:3000/api）③ 手機與電腦須同一 Wi‑Fi。"
            case .timedOut:
                return "連線逾時。\(base)\(urlNote)\n\n請確認後端已啟動、防火牆允許，且 API 網址正確。"
            case .notConnectedToInternet:
                return "未連上網路。\(base)"
            case .secureConnectionFailed, .serverCertificateUntrusted:
                return "TLS／憑證問題。\(base)\(urlNote)"
            default:
                break
            }
        }

        return "\(base)\(urlNote)"
    }
}
