import Foundation

/// 將 API／後端錯誤轉成使用者可讀的繁中訊息（不直接顯示原始 JSON 或 HTTP 原文）。
enum UserFacingErrorMessage {
    private struct APIErrorResponse: Decodable {
        struct ErrorDetail: Decodable {
            let code: String?
            let message: String?
        }

        let error: ErrorDetail?
        let message: String?
    }

    static func message(for error: Error) -> String {
        if let api = error as? APIRequestError {
            return api.userFacingMessage
        }
        if let localized = error as? LocalizedError,
           let text = localized.errorDescription?.trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty
        {
            return sanitizeIfNeeded(text) ?? "操作失敗，請稍後再試"
        }
        return "操作失敗，請稍後再試"
    }

    static func messageForHTTPStatus(code: Int, body: String?) -> String {
        let parsed = parseBackendBody(body)
        return resolve(code: code, backendCode: parsed.code, backendMessage: parsed.message)
    }

    static func messageForDecodingFailure() -> String {
        "無法解析伺服器回應，請稍後再試"
    }

    // MARK: - Private

    private static func parseBackendBody(_ body: String?) -> (code: String?, message: String?) {
        guard let body else { return (nil, nil) }
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return (nil, nil) }

        if let data = trimmed.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(APIErrorResponse.self, from: data)
        {
            let code = decoded.error?.code?.trimmingCharacters(in: .whitespacesAndNewlines)
            let message = (decoded.error?.message ?? decoded.message)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (
                code?.isEmpty == false ? code : nil,
                message?.isEmpty == false ? message : nil
            )
        }

        if !trimmed.hasPrefix("{"), !trimmed.hasPrefix("[") {
            return (nil, trimmed)
        }
        return (nil, nil)
    }

    private static func resolve(code: Int, backendCode: String?, backendMessage: String?) -> String {
        if let translated = translateKnownEnglish(backendMessage) {
            return translated
        }

        if let readable = sanitizeIfNeeded(backendMessage ?? "") {
            return readable
        }

        let normalizedCode = backendCode?
            .uppercased()
            .replacingOccurrences(of: "-", with: "_")

        if let mapped = mapByErrorCode(normalizedCode, httpStatus: code) {
            return mapped
        }

        return defaultMessage(forHTTPStatus: code)
    }

    private static func mapByErrorCode(_ code: String?, httpStatus: Int) -> String? {
        switch code {
        case "INVALID_CREDENTIALS":
            return "帳號或密碼錯誤，請再試一次"
        case "UNAUTHORIZED":
            return "登入已過期，請重新登入"
        case "FORBIDDEN":
            return "您沒有權限執行此操作"
        case "NOT_FOUND", "PROJECT_NOT_FOUND", "QUALITY_TASK_NOT_FOUND", "QUALITY_DRAWING_NOT_FOUND":
            return "找不到指定資料"
        case "VALIDATION_ERROR", "UNPROCESSABLE_ENTITY", "BAD_REQUEST":
            return nil
        case "CONFLICT", "EMAIL_CONFLICT", "USERNAME_CONFLICT":
            return nil
        case "FILE_TOO_LARGE", "PAYLOAD_TOO_LARGE":
            return "檔案大小超過限制"
        case "UNSUPPORTED_FILE_TYPE":
            return "不支援的檔案類型"
        case "TOO_MANY_REQUESTS":
            return "請求過於頻繁，請稍後再試"
        case "INTERNAL_SERVER_ERROR", "DATABASE_ERROR", "SERVICE_UNAVAILABLE":
            return "伺服器發生錯誤，請稍後再試"
        case "NETWORK_ERROR":
            return "網路連線異常，請確認連線後再試"
        default:
            if httpStatus == 401 { return "登入已過期，請重新登入" }
            if httpStatus == 403 { return "您沒有權限執行此操作" }
            return nil
        }
    }

    private static func translateKnownEnglish(_ message: String?) -> String? {
        guard let message else { return nil }
        let lower = message.lowercased()
        if lower.contains("invalid credentials") { return "帳號或密碼錯誤，請再試一次" }
        if lower.contains("access denied") { return "您沒有權限執行此操作" }
        if lower == "unauthorized" { return "登入已過期，請重新登入" }
        if lower.contains("record not found") || lower.contains("not found") {
            return "找不到指定資料"
        }
        if lower.contains("too many requests") { return "請求過於頻繁，請稍後再試" }
        if lower.contains("payload too large") || lower.contains("file size") {
            return "檔案大小超過限制"
        }
        if lower.contains("internal server error") { return "伺服器發生錯誤，請稍後再試" }
        if lower.contains("network") && lower.contains("error") {
            return "網路連線異常，請確認連線後再試"
        }
        return nil
    }

    /// 後端若已回繁中且非技術性內容，可直接顯示。
    private static func sanitizeIfNeeded(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.contains("HTTP ") && trimmed.contains("{") { return nil }
        if trimmed.hasPrefix("{") || trimmed.hasPrefix("[") { return nil }
        if trimmed.count > 280 { return String(trimmed.prefix(280)) + "…" }
        if containsMostlyChinese(trimmed) || !looksLikeTechnicalEnglish(trimmed) {
            return trimmed
        }
        return nil
    }

    private static func containsMostlyChinese(_ text: String) -> Bool {
        var cjk = 0
        var letters = 0
        for scalar in text.unicodeScalars {
            if (0x4E00 ... 0x9FFF).contains(scalar.value) {
                cjk += 1
            } else if CharacterSet.letters.contains(scalar) {
                letters += 1
            }
        }
        return cjk >= 2 || (cjk > 0 && cjk >= letters / 2)
    }

    private static func looksLikeTechnicalEnglish(_ text: String) -> Bool {
        let lower = text.lowercased()
        let markers = [
            "error", "exception", "prisma", "stack", "undefined", "null",
            "econnrefused", "etimedout", "internal server",
        ]
        return markers.contains { lower.contains($0) } && !containsMostlyChinese(text)
    }

    private static func defaultMessage(forHTTPStatus status: Int) -> String {
        switch status {
        case 400:
            return "請求內容有誤，請檢查後再試"
        case 401:
            return "登入已過期，請重新登入"
        case 403:
            return "您沒有權限執行此操作"
        case 404:
            return "找不到指定資料"
        case 409:
            return "資料衝突，請重新整理後再試"
        case 413:
            return "檔案大小超過限制"
        case 422:
            return "資料驗證失敗，請檢查輸入內容"
        case 429:
            return "請求過於頻繁，請稍後再試"
        case 500...599:
            return "伺服器忙碌中，請稍後再試"
        default:
            return "操作失敗，請稍後再試"
        }
    }
}

extension APIRequestError {
    var userFacingMessage: String {
        switch self {
        case .invalidURL:
            return "連線設定有誤，請聯絡管理員"
        case .apiMustUseHTTPS:
            return "API 必須使用安全連線"
        case .invalidResponse:
            return "伺服器回應異常，請稍後再試"
        case let .httpStatus(code, body):
            return UserFacingErrorMessage.messageForHTTPStatus(code: code, body: body)
        case .decoding:
            return UserFacingErrorMessage.messageForDecodingFailure()
        case let .transport(error, attemptedURL):
            return Self.transportMessage(error: error, attemptedURL: attemptedURL)
        }
    }
}

extension Error {
    /// 顯示給使用者的錯誤說明（優先於 `localizedDescription`）。
    var userFacingMessage: String {
        UserFacingErrorMessage.message(for: self)
    }
}
