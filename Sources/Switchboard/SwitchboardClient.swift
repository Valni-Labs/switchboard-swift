
import Foundation

public final class Client: Sendable {
    public static let defaultBaseURL = URL(string: "https://switchboard.valni.app")!

    static let maxErrorBodyBytes = 64 * 1024

    private let apiKey: String
    private let baseURL: URL
    private let urlSession: URLSession

    public init(
        apiKey: String,
        baseURL: URL = Client.defaultBaseURL,
        urlSession: URLSession = .shared,
    ) {
        self.apiKey = apiKey
        self.baseURL = baseURL
        self.urlSession = urlSession
    }

    public func usage(
        endUserID: String? = nil,
        since: Int? = nil,
        until: Int? = nil,
        limit: Int? = nil,
        beforeAt: Int? = nil,
        beforeID: Int? = nil,
    ) async throws -> UsagePage {
        var queryItems: [URLQueryItem] = []
        if let endUserID { queryItems.append(URLQueryItem(name: "user_id", value: endUserID)) }
        if let since { queryItems.append(URLQueryItem(name: "since", value: String(since))) }
        if let until { queryItems.append(URLQueryItem(name: "until", value: String(until))) }
        if let limit { queryItems.append(URLQueryItem(name: "limit", value: String(limit))) }
        if let beforeAt { queryItems.append(URLQueryItem(name: "before_at", value: String(beforeAt))) }
        if let beforeID { queryItems.append(URLQueryItem(name: "before_id", value: String(beforeID))) }
        let urlRequest = try buildURLRequest(path: "/v1/switchboard/usage", queryItems: queryItems)
        let (data, response) = try await performData(urlRequest)
        try ensureSuccess(response: response, body: data)
        do {
            return try Self.jsonDecoder.decode(UsagePage.self, from: data)
        } catch {
            throw SwitchboardError.decodingFailed(underlying: error)
        }
    }

    public func models() async throws -> ModelsPage {
        let urlRequest = try buildURLRequest(path: "/v1/models")
        let (data, response) = try await performData(urlRequest)
        try ensureSuccess(response: response, body: data)
        do {
            return try Self.jsonDecoder.decode(ModelsPage.self, from: data)
        } catch {
            throw SwitchboardError.decodingFailed(underlying: error)
        }
    }

    func buildURLRequest<Body: Encodable>(path: String, body: Body) throws -> URLRequest {
        var request = try buildURLRequest(path: path)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        do {
            request.httpBody = try Self.jsonEncoder.encode(body)
        } catch {
            throw SwitchboardError.encodingFailed(underlying: error)
        }
        return request
    }

    func buildURLRequest(path: String) throws -> URLRequest {
        try buildURLRequest(path: path, queryItems: [])
    }

    func buildURLRequest(path: String, queryItems: [URLQueryItem]) throws -> URLRequest {
        guard !apiKey.isEmpty else { throw SwitchboardError.missingAPIKey }
        var url = baseURL.appendingPathComponent(path.trimmingPrefix("/"))
        if !queryItems.isEmpty {
            guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
                throw SwitchboardError.encodingFailed(underlying: URLError(.badURL))
            }
            components.queryItems = queryItems
            guard let urlWithQuery = components.url else {
                throw SwitchboardError.encodingFailed(underlying: URLError(.badURL))
            }
            url = urlWithQuery
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        return request
    }

    func performData(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await urlSession.data(for: request)
        } catch {
            throw SwitchboardError.transportError(underlying: error)
        }
    }

    func performBytes(_ request: URLRequest) async throws -> (URLSession.AsyncBytes, URLResponse) {
        do {
            return try await urlSession.bytes(for: request)
        } catch {
            throw SwitchboardError.transportError(underlying: error)
        }
    }

    func ensureSuccess(response: URLResponse, body: Data) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SwitchboardError.serverError(status: 0, code: nil, message: "Response was not an HTTPURLResponse", context: nil)
        }
        let status = httpResponse.statusCode
        guard !(200...299).contains(status) else { return }
        if body.isEmpty {
            throw SwitchboardError.serverError(status: status, code: nil, message: "Empty response body", context: nil)
        }
        if let envelope = try? Self.jsonDecoder.decode(ServerErrorEnvelope.self, from: body) {
            let context = ServerErrorContext(
                model: envelope.model,
                provider: envelope.provider,
                spentMicros: envelope.spentMicros,
                capMicros: envelope.capMicros,
                retryAfterSeconds: envelope.retryAfterSeconds,
            )
            throw SwitchboardError.serverError(status: status, code: envelope.code, message: envelope.error, context: context)
        }
        let message = String(data: body, encoding: .utf8) ?? "Unparseable error body"
        throw SwitchboardError.serverError(status: status, code: nil, message: message, context: nil)
    }

    private static let jsonEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        return encoder
    }()

    private static let jsonDecoder = JSONDecoder()
}

private extension String {
    func trimmingPrefix(_ prefix: String) -> String {
        hasPrefix(prefix) ? String(dropFirst(prefix.count)) : self
    }
}
