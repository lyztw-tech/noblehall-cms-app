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
        userFacingMessage
    }

    static func transportMessage(error: Error, attemptedURL: URL?) -> String {
        if let urlErr = error as? URLError {
            switch urlErr.code {
            case .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed:
                return "無法連到伺服器，請確認後端已啟動且手機與電腦在同一網路。"
            case .timedOut:
                return "連線逾時，請稍後再試。"
            case .notConnectedToInternet:
                return "目前無網路連線，請檢查網路設定。"
            case .secureConnectionFailed, .serverCertificateUntrusted:
                return "安全連線失敗，請確認 API 網址與憑證設定。"
            default:
                break
            }
        }
        return "網路連線異常，請稍後再試"
    }
}
