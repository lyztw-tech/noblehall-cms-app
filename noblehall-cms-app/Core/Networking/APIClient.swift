import Foundation

// MARK: - 編碼／解碼
// 明確 `nonisolated`：專案若啟用 default MainActor isolation，`actor APIClient` 的 `init`／`shared`
// 會在非隔離脈絡執行，不得呼叫預設隔離到 MainActor 的靜態方法。

private enum APIClientCodec: Sendable {
    /// 使用 `FormatStyle` 解析，避免 Swift 6 SDK 將 `ISO8601DateFormatter` 標為 `@MainActor` 導致
    /// `JSONDecoder` 自訂策略在非隔離脈絡無法呼叫 `date(from:)`。
    nonisolated private static func parseAPIDateString(_ string: String) -> Date? {
        let withFraction = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
        if let d = try? Date(string, strategy: withFraction) {
            return d
        }
        let plain = Date.ISO8601FormatStyle(includingFractionalSeconds: false)
        return try? Date(string, strategy: plain)
    }

    /// `any Encodable` 存入 `@unchecked Sendable` 包裝，供 JSONEncoder 使用（呼叫端傳入的 body 應僅在請求執行緒使用）。
    private struct ErasedEncodable: Encodable, @unchecked Sendable {
        nonisolated(unsafe) let value: any Encodable
        nonisolated init(_ value: any Encodable) { self.value = value }
        nonisolated func encode(to encoder: Encoder) throws {
            try value.encode(to: encoder)
        }
    }

    nonisolated static func makeJSONDecoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { dec in
            let c = try dec.singleValueContainer()
            let s = try c.decode(String.self)
            guard let date = Self.parseAPIDateString(s) else {
                throw DecodingError.dataCorruptedError(in: c, debugDescription: "Invalid date: \(s)")
            }
            return date
        }
        return d
    }

    nonisolated private static func appendUTF8(_ string: String, to data: inout Data) {
        guard let bytes = string.data(using: .utf8) else { return }
        data.append(contentsOf: bytes)
    }

    nonisolated static func sanitizedMultipartFilename(_ raw: String) -> String {
        var base = (raw as NSString).lastPathComponent
        if base.isEmpty { base = "file" }
        base = base.replacingOccurrences(of: "..", with: "_")
        base = base
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "\\", with: "_")
            .replacingOccurrences(of: ":", with: "_")
            .replacingOccurrences(of: "\"", with: "_")
        if base.count > 200 {
            let ext = (base as NSString).pathExtension
            let stem = (base as NSString).deletingPathExtension
            let maxStem = max(1, 200 - ext.count - (ext.isEmpty ? 0 : 1))
            base = String(stem.prefix(maxStem)) + (ext.isEmpty ? "" : ".\(ext)")
        }
        return base
    }

    nonisolated static func buildMultipartBody(boundary: String, fields: [String: String], files: [MultipartFilePart]) -> Data {
        var body = Data()
        for (name, value) in fields {
            appendUTF8("--\(boundary)\r\n", to: &body)
            appendUTF8("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n", to: &body)
            appendUTF8(value, to: &body)
            appendUTF8("\r\n", to: &body)
        }
        for file in files {
            let safeFilename = sanitizedMultipartFilename(file.filename)
            appendUTF8("--\(boundary)\r\n", to: &body)
            appendUTF8(
                "Content-Disposition: form-data; name=\"\(file.fieldName)\"; filename=\"\(safeFilename)\"\r\n",
                to: &body
            )
            appendUTF8("Content-Type: \(file.mimeType)\r\n\r\n", to: &body)
            body.append(file.data)
            appendUTF8("\r\n", to: &body)
        }
        appendUTF8("--\(boundary)--\r\n", to: &body)
        return body
    }

    nonisolated static func encodeJSONRequestBody(_ body: any Encodable) throws -> Data {
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        return try enc.encode(ErasedEncodable(body))
    }
}

/// 與 Construction Dashboard API 通訊。使用 JWT Bearer token。
actor APIClient {
    static let shared = APIClient()

    private let session: URLSession
    private let decoder: JSONDecoder

    init(
        configuration: URLSessionConfiguration = {
            let c = URLSessionConfiguration.default
            c.httpCookieStorage = nil
            c.httpCookieAcceptPolicy = .never
            c.timeoutIntervalForRequest = 45
            c.timeoutIntervalForResource = 120
            return c
        }()
    ) {
        session = URLSession(configuration: configuration)
        decoder = APIClientCodec.makeJSONDecoder()
    }

    func send<R: Decodable>(
        _ method: HTTPMethod,
        path: String,
        queryItems: [URLQueryItem]? = nil,
        body: Encodable? = nil
    ) async throws -> R {
        let data = try await perform(method, path: path, queryItems: queryItems, body: body)
        do {
            return try decoder.decode(R.self, from: data)
        } catch {
            throw APIRequestError.decoding(error)
        }
    }

    /// 不需解析 body（例如 204、空回應）。
    func sendVoid(
        _ method: HTTPMethod,
        path: String,
        queryItems: [URLQueryItem]? = nil,
        body: Encodable? = nil
    ) async throws {
        _ = try await perform(method, path: path, queryItems: queryItems, body: body)
    }

    /// 下載需登入的資源（例如 `GET /files/:id`）。勿用 `AsyncImage` 直連此類 URL。
    func fetchBinary(url: URL) async throws -> Data {
        try AppConfiguration.validateAPIBaseIsSecureForRequests()
        let fetchURL = Self.normalizedAssetFetchURL(url) ?? url
        guard Self.isSameOrigin(asAPIHost: fetchURL, serverOrigin: AppConfiguration.serverOriginURL) else {
            throw APIRequestError.invalidURL
        }

        var request = URLRequest(url: fetchURL)
        request.httpMethod = HTTPMethod.GET.rawValue
        request.cachePolicy = .reloadIgnoringLocalCacheData
        applyCommonHeaders(to: &request)

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIRequestError.transport(error, attemptedURL: url)
        }
        guard let http = response as? HTTPURLResponse else { throw APIRequestError.invalidResponse }
        guard (200 ... 299).contains(http.statusCode) else {
            let text = String(data: data, encoding: .utf8)
            throw APIRequestError.httpStatus(code: http.statusCode, body: text)
        }
        return data
    }

    /// `multipart/form-data`（例如照片上傳）。與 `send` 相同 Bearer token。
    func sendMultipart<R: Decodable>(
        _ method: HTTPMethod,
        path: String,
        queryItems: [URLQueryItem]? = nil,
        fields: [String: String],
        files: [MultipartFilePart]
    ) async throws -> R {
        try AppConfiguration.validateAPIBaseIsSecureForRequests()
        var components = URLComponents(url: AppConfiguration.apiRootURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        components?.queryItems = queryItems?.filter { !($0.value ?? "").isEmpty }
        guard let url = components?.url else { throw APIRequestError.invalidURL }

        let boundary = "ConstructionDashboardFormBoundary" + UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let body = APIClientCodec.buildMultipartBody(boundary: boundary, fields: fields, files: files)

        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.httpMethod = method.rawValue
        request.httpBody = body
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")
        request.setValue("ConstructionDashboard-iOS/\(AppMetadata.version)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 300
        if let token = AuthTokenStore.accessToken, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIRequestError.transport(error, attemptedURL: url)
        }
        guard let http = response as? HTTPURLResponse else { throw APIRequestError.invalidResponse }
        guard (200 ... 299).contains(http.statusCode) else {
            let text = String(data: data, encoding: .utf8)
            throw APIRequestError.httpStatus(code: http.statusCode, body: text)
        }
        do {
            return try decoder.decode(R.self, from: data)
        } catch {
            throw APIRequestError.decoding(error)
        }
    }

    private func perform(
        _ method: HTTPMethod,
        path: String,
        queryItems: [URLQueryItem]?,
        body: Encodable?,
        retryingAfterRefresh: Bool = false
    ) async throws -> Data {
        let url = try makeURL(path: path, queryItems: queryItems)
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.httpMethod = method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue("no-cache", forHTTPHeaderField: "Pragma")
        applyCommonHeaders(to: &request)
        if let body {
            request.httpBody = try APIClientCodec.encodeJSONRequestBody(body)
        }

        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw APIRequestError.transport(error, attemptedURL: url)
        }
        guard let http = response as? HTTPURLResponse else { throw APIRequestError.invalidResponse }

        if http.statusCode == 401, !retryingAfterRefresh, shouldAttemptRefresh(for: path) {
            try await refreshAccessToken()
            return try await perform(method, path: path, queryItems: queryItems, body: body, retryingAfterRefresh: true)
        }

        guard (200 ... 299).contains(http.statusCode) else {
            let text = String(data: data, encoding: .utf8)
            throw APIRequestError.httpStatus(code: http.statusCode, body: text)
        }
        return data
    }

    private func makeURL(path: String, queryItems: [URLQueryItem]?) throws -> URL {
        try AppConfiguration.validateAPIBaseIsSecureForRequests()
        var components = URLComponents(url: AppConfiguration.apiRootURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        components?.queryItems = queryItems?.filter { !($0.value ?? "").isEmpty }
        guard let url = components?.url else { throw APIRequestError.invalidURL }
        return url
    }

    private func applyCommonHeaders(to request: inout URLRequest) {
        request.setValue("ConstructionDashboard-iOS/\(AppMetadata.version)", forHTTPHeaderField: "User-Agent")
        if let token = AuthTokenStore.accessToken, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
    }

    private func shouldAttemptRefresh(for path: String) -> Bool {
        !path.hasPrefix("auth/login") && !path.hasPrefix("auth/refresh")
    }

    private func refreshAccessToken() async throws {
        guard let refreshToken = AuthTokenStore.refreshToken, !refreshToken.isEmpty else {
            throw APIRequestError.httpStatus(code: 401, body: nil)
        }
        let data = try await perform(
            .POST,
            path: "auth/refresh",
            queryItems: nil,
            body: RefreshTokenRequestBody(refreshToken: refreshToken),
            retryingAfterRefresh: true
        )
        do {
            let envelope = try decoder.decode(APIDataEnvelope<RefreshTokenResponseDto>.self, from: data)
            AuthTokenStore.save(accessToken: envelope.data.accessToken, refreshToken: envelope.data.refreshToken)
        } catch {
            AuthTokenStore.clear()
            throw APIRequestError.decoding(error)
        }
    }

    /// 後端若回傳 `localhost` 等與 App 設定的 API host 不同，仍允許 `/files/` 路徑改寫後下載。
    private static func normalizedAssetFetchURL(_ url: URL) -> URL? {
        let path = url.path
        guard path.contains("/files/") else { return nil }
        let origin = AppConfiguration.serverOriginURL
        guard var comp = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        comp.scheme = origin.scheme
        comp.host = origin.host
        comp.port = origin.port
        return comp.url
    }

    /// 資產 URL 須與 `serverOriginURL`（`API_BASE_URL` 去掉最後一段 path）同源，避免任意 URL 讀取。
    private static func isSameOrigin(asAPIHost asset: URL, serverOrigin: URL) -> Bool {
        guard let ah = asset.host, let sh = serverOrigin.host,
              ah.caseInsensitiveCompare(sh) == .orderedSame else { return false }
        let asc = (asset.scheme ?? "").lowercased()
        let ssc = (serverOrigin.scheme ?? "").lowercased()
        guard asc == ssc, !asc.isEmpty else { return false }
        return effectivePort(for: asset) == effectivePort(for: serverOrigin)
    }

    private static func effectivePort(for url: URL) -> Int {
        if let p = url.port { return p }
        return (url.scheme?.lowercased() == "https") ? 443 : 80
    }
}

struct MultipartFilePart: Sendable {
    let fieldName: String
    let filename: String
    let mimeType: String
    let data: Data
}
