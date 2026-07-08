
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

    public func chatCompletions(_ request: Chat.Request) async throws -> Chat.Response {
        let urlRequest = try buildURLRequest(path: "/v1/chat/completions", body: request)
        let (data, response) = try await performData(urlRequest)
        try ensureSuccess(response: response, body: data)
        do {
            return try Self.jsonDecoder.decode(Chat.Response.self, from: data)
        } catch {
            throw SwitchboardError.decodingFailed(underlying: error)
        }
    }

    public func streamChatCompletions(
        _ request: Chat.Request,
    ) -> AsyncThrowingStream<Chat.StreamChunk, Error> {
        AsyncThrowingStream { continuation in
            let streamingRequest = Chat.Request(
                model: request.model,
                messages: request.messages,
                temperature: request.temperature,
                maxTokens: request.maxTokens,
                topP: request.topP,
                stream: true,
                stopSequences: request.stopSequences,
                tools: request.tools,
                user: request.user,
            )

            let task = Task {
                do {
                    let urlRequest = try self.buildURLRequest(path: "/v1/chat/completions", body: streamingRequest)
                    let (bytes, response) = try await self.performBytes(urlRequest)
                    if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
                        var collected = Data()
                        for try await byte in bytes {
                            collected.append(byte)
                            if collected.count > Self.maxErrorBodyBytes { break }
                        }
                        try self.ensureSuccess(response: response, body: collected)
                    }
                    var sawDone = false
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        if payload.isEmpty { continue }
                        if payload == "[DONE]" {
                            sawDone = true
                            break
                        }
                        guard let json = payload.data(using: .utf8) else { continue }
                        do {
                            let chunk = try Self.jsonDecoder.decode(Chat.StreamChunk.self, from: json)
                            continuation.yield(chunk)
                        } catch {
                            continuation.finish(throwing: SwitchboardError.decodingFailed(underlying: error))
                            return
                        }
                    }
                    if !sawDone {
                        continuation.finish(throwing: SwitchboardError.streamTruncated)
                    } else {
                        continuation.finish()
                    }
                } catch let error as SwitchboardError {
                    continuation.finish(throwing: error)
                } catch {
                    continuation.finish(throwing: SwitchboardError.transportError(underlying: error))
                }
            }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    public func models() async throws -> [PickerModel] {
        let urlRequest = try buildURLRequest(path: "/v1/models")
        let (data, response) = try await performData(urlRequest)
        try ensureSuccess(response: response, body: data)
        do {
            let envelope = try Self.jsonDecoder.decode(PickerModelsEnvelope.self, from: data)
            return envelope.models
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
        guard !apiKey.isEmpty else { throw SwitchboardError.missingAPIKey }
        let url = baseURL.appendingPathComponent(path.trimmingPrefix("/"))
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
        if let envelope = try? Self.jsonDecoder.decode(ErrorEnvelope.self, from: body) {
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

    private struct PickerModelsEnvelope: Decodable {
        let models: [PickerModel]
    }

    private struct ErrorEnvelope: Decodable {
        let code: String
        let error: String
        let model: String?
        let provider: String?
        let spentMicros: Int?
        let capMicros: Int?
        let retryAfterSeconds: Int?
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
