import Foundation
import SwitchboardNative

public final class GenericProvider: RawGenerationProvider, @unchecked Sendable {
    public let baseURL: URL
    public let contextLimits: ModelLimits
    public let preferredToolCallMode: ToolCallMode
    public let supportsVision: Bool
    private let apiKey: String
    private let urlSession: URLSession
    private var currentTask: Task<Void, Never>?
    public private(set) var lastUsage: GenerationUsage?

    static let chatCompletionsPath = "chat/completions"

    public init(
        baseURL: URL,
        apiKey: String,
        contextLimits: ModelLimits = .remoteDefault,
        preferredToolCallMode: ToolCallMode = .native,
        supportsVision: Bool = false,
        urlSession: URLSession = .shared
    ) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.contextLimits = contextLimits
        self.preferredToolCallMode = preferredToolCallMode
        self.supportsVision = supportsVision
        self.urlSession = urlSession
    }

    public func generate(_ body: RouterBody) -> AsyncThrowingStream<GenerationChunk, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                self.lastUsage = nil
                guard case .openaiGeneric = body else {
                    continuation.finish(throwing: ProviderError.requestInvalid(
                        message: "GenericProvider serves OpenAI-compatible endpoints and accepts only the openai_generic kind.",
                    ))
                    return
                }
                let streamingBody = body.streaming()
                guard case .openaiGeneric(let chatRequest) = streamingBody else {
                    continuation.finish(throwing: ProviderError.requestInvalid(
                        message: "GenericProvider serves OpenAI-compatible endpoints and accepts only the openai_generic kind.",
                    ))
                    return
                }
                var reducer = OpenAIChatStreamReducer()
                var capturedUsage: GenerationUsage?
                do {
                    let request = try self.buildRequest(chatRequest)
                    let (bytes, response) = try await self.urlSession.bytes(for: request)

                    if let http = response as? HTTPURLResponse {
                        if http.statusCode == 401 {
                            continuation.finish(throwing: ProviderError.unauthorized)
                            return
                        }
                        guard (200..<300).contains(http.statusCode) else {
                            continuation.finish(throwing: ProviderError.notConfigured("Server returned \(http.statusCode)"))
                            return
                        }
                    }

                    let decoder = JSONDecoder()
                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        if payload.isEmpty { continue }
                        guard payload != NativeStreamDecoding.doneSentinel else { break }
                        guard let data = payload.data(using: .utf8),
                              let chunk = try? decoder.decode(OpenAIChatChunk.self, from: data) else { continue }
                        let reduction = reducer.reduce(event: .openaiGeneric(chunk))
                        for generated in reduction.chunks {
                            continuation.yield(generated)
                        }
                        if let usage = reduction.usage { capturedUsage = usage }
                    }
                    self.lastUsage = capturedUsage
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            self.currentTask = task
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func abort() {
        currentTask?.cancel()
        currentTask = nil
    }

    private func buildRequest(_ chatRequest: OpenAIChatRequest) throws -> URLRequest {
        let url = baseURL.appendingPathComponent(Self.chatCompletionsPath)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        do {
            request.httpBody = try JSONEncoder().encode(chatRequest)
        } catch {
            throw SwitchboardError.encodingFailed(underlying: error)
        }
        return request
    }
}
