import Foundation

struct NotificationSSEEvent: Sendable {
    enum Kind: Sendable {
        case new(title: String?, body: String?, link: String?)
        case readUpdate
        case unknown
    }

    let kind: Kind
}

/// Construction Dashboard MVP 沒有通知 SSE；保留型別相容，實際更新由 `NotificationInboxStore` 輪詢。
actor NotificationSSEClient {
    static let shared = NotificationSSEClient()

    private var task: Task<Void, Never>?
    private var generation: UInt = 0

    func start(spaceId: String, onEvent: @escaping @MainActor (NotificationSSEEvent) async -> Void) {
        stop()
        _ = (spaceId, onEvent)
    }

    func stop() {
        task?.cancel()
        task = nil
        generation &+= 1
    }

    private func runLoop(
        spaceId: String,
        generation: UInt,
        onEvent: @escaping @MainActor (NotificationSSEEvent) async -> Void
    ) async {
        var retry = 0
        while !Task.isCancelled, self.generation == generation {
            do {
                try await consumeStream(spaceId: spaceId, onEvent: onEvent)
                retry = 0
            } catch {
                if Task.isCancelled || self.generation != generation { return }
                retry += 1
                let delaySec = min(retry, 8)
                try? await Task.sleep(nanoseconds: UInt64(delaySec) * 1_000_000_000)
            }
        }
    }

    private func consumeStream(
        spaceId: String,
        onEvent: @escaping @MainActor (NotificationSSEEvent) async -> Void
    ) async throws {
        try AppConfiguration.validateAPIBaseIsSecureForRequests()
        let url = AppConfiguration.apiRootURL.appendingPathComponent("notifications/stream")
        var request = URLRequest(url: url)
        request.httpMethod = HTTPMethod.GET.rawValue
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue(spaceId, forHTTPHeaderField: "x-space-id")
        request.setValue("NoblehallCMS-iOS/\(AppMetadata.version)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = .infinity

        let config = URLSessionConfiguration.default
        config.httpCookieStorage = .shared
        config.httpCookieAcceptPolicy = .always
        config.waitsForConnectivity = true
        config.timeoutIntervalForRequest = .infinity
        config.timeoutIntervalForResource = .infinity
        let urlSession = URLSession(configuration: config)

        let (bytes, response) = try await urlSession.bytes(for: request)
        guard let http = response as? HTTPURLResponse else { throw APIRequestError.invalidResponse }
        guard (200 ... 299).contains(http.statusCode) else {
            throw APIRequestError.httpStatus(code: http.statusCode, body: nil)
        }

        for try await line in bytes.lines {
            if Task.isCancelled { return }
            if line.hasPrefix(":") { continue }

            if line.hasPrefix("data:") {
                let payload = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                guard !payload.isEmpty, let event = parseDataLine(payload) else { continue }
                await onEvent(event)
                continue
            }

            if line.isEmpty { continue }
        }
    }

    private func parseDataLine(_ json: String) -> NotificationSSEEvent? {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = obj["type"] as? String
        else { return nil }

        switch type {
        case "new":
            return NotificationSSEEvent(
                kind: .new(
                    title: obj["title"] as? String,
                    body: obj["body"] as? String,
                    link: obj["link"] as? String
                )
            )
        case "read-update":
            return NotificationSSEEvent(kind: .readUpdate)
        default:
            return NotificationSSEEvent(kind: .unknown)
        }
    }
}
