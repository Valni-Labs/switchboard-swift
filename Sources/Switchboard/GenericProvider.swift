import Foundation

public final class GenericProvider: RawGenerationProvider, @unchecked Sendable {
    public let baseURL: URL
    public let modelID: String
    public let contextLimits: ModelLimits
    public let preferredToolCallMode: ToolCallMode
    public let supportsVision: Bool
    private let apiKey: String
    private var currentTask: Task<Void, Never>?
    public private(set) var lastUsage: GenerationUsage?

    public init(
        baseURL: URL,
        modelID: String,
        apiKey: String,
        contextLimits: ModelLimits = .remoteDefault,
        preferredToolCallMode: ToolCallMode = .native,
        supportsVision: Bool = false
    ) {
        self.baseURL = baseURL
        self.modelID = modelID
        self.apiKey = apiKey
        self.contextLimits = contextLimits
        self.preferredToolCallMode = preferredToolCallMode
        self.supportsVision = supportsVision
    }

    public func generateRaw(messages: [ChatMessage]) -> AsyncThrowingStream<RawStreamChunk, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                self.lastUsage = nil
                var capturedUsage: GenerationUsage?
                do {
                    let request = try self.buildRequest(messages: messages, tools: nil)
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)

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

                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        guard line.hasPrefix("data: ") else { continue }
                        let payload = String(line.dropFirst(6))
                        guard payload != "[DONE]" else { break }
                        guard let data = payload.data(using: .utf8),
                              let chunk = try? JSONDecoder().decode(GenericStreamChunk.self, from: data) else { continue }
                        if let usage = chunk.usage {
                            capturedUsage = GenerationUsage(
                                inputTokens: usage.promptTokens,
                                outputTokens: usage.completionTokens
                            )
                            continue
                        }
                        guard let content = chunk.choices.first?.delta.content, !content.isEmpty else { continue }
                        continuation.yield(.text(content))
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

    public func generateNative(
        messages: [ChatMessage],
        tools: [ToolSchema]
    ) -> AsyncThrowingStream<NativeStreamChunk, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                self.lastUsage = nil
                var capturedUsage: GenerationUsage?
                do {
                    let request = try self.buildRequest(messages: messages, tools: tools)
                    let (bytes, response) = try await URLSession.shared.bytes(for: request)

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

                    var buffer: [Int: ToolCallBuffer] = [:]

                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        guard line.hasPrefix("data: ") else { continue }
                        let payload = String(line.dropFirst(6))
                        guard payload != "[DONE]" else { break }
                        guard let data = payload.data(using: .utf8),
                              let chunk = try? JSONDecoder().decode(GenericToolStreamChunk.self, from: data) else { continue }

                        if let usage = chunk.usage {
                            capturedUsage = GenerationUsage(
                                inputTokens: usage.promptTokens,
                                outputTokens: usage.completionTokens
                            )
                        }

                        guard let choice = chunk.choices.first else { continue }

                        if let content = choice.delta.content, !content.isEmpty {
                            continuation.yield(.text(content))
                        }

                        if let toolCallDeltas = choice.delta.toolCalls {
                            for delta in toolCallDeltas {
                                var entry = buffer[delta.index] ?? ToolCallBuffer()
                                if let id = delta.id { entry.id = id }
                                if let name = delta.function?.name { entry.name = name }
                                if let argsDelta = delta.function?.arguments { entry.arguments += argsDelta }
                                buffer[delta.index] = entry
                            }
                        }
                    }

                    for index in buffer.keys.sorted() {
                        let entry = buffer[index]!
                        guard let id = entry.id, let name = entry.name else { continue }
                        continuation.yield(.toolCall(id: id, name: name, argumentsJSON: entry.arguments))
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

    private func buildRequest(messages: [ChatMessage], tools: [ToolSchema]?) throws -> URLRequest {
        if !supportsVision, messages.contains(where: \.hasNonTextContent) {
            throw RoutingError.imagesNotSupportedByModel(modelID: modelID)
        }
        let endpoint = baseURL.appendingPathComponent("chat/completions")
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !apiKey.isEmpty {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        let body = GenericChatRequest(
            model: modelID,
            messages: messages.map(GenericWireMessage.init(from:)),
            tools: tools.map { schemas in schemas.map(GenericChatRequest.Tool.init(from:)) }
        )
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }
}

private struct ToolCallBuffer {
    var id: String?
    var name: String?
    var arguments: String = ""
}

private struct GenericChatRequest: Encodable {
    let model: String
    let messages: [GenericWireMessage]
    let stream: Bool = true
    let streamOptions = StreamOptions(includeUsage: true)
    let tools: [Tool]?

    enum CodingKeys: String, CodingKey {
        case model, messages, stream, tools
        case streamOptions = "stream_options"
    }

    struct StreamOptions: Encodable {
        let includeUsage: Bool

        enum CodingKeys: String, CodingKey {
            case includeUsage = "include_usage"
        }
    }

    struct Tool: Encodable {
        let type: String
        let function: Function

        init(from schema: ToolSchema) {
            self.type = "function"
            self.function = Function(
                name: schema.name,
                description: schema.description,
                parameters: Parameters(from: schema.parameters)
            )
        }

        struct Function: Encodable {
            let name: String
            let description: String
            let parameters: Parameters
        }

        struct Parameters: Encodable {
            let type: String = "object"
            let properties: [String: PropertySchema]
            let required: [String]

            init(from parameters: [ToolParameter]) {
                self.properties = Dictionary(
                    uniqueKeysWithValues: parameters.map { p in
                        (p.name, PropertySchema(type: PropertySchema.normaliseType(p.type), description: p.description))
                    }
                )
                self.required = parameters.filter(\.required).map(\.name)
            }
        }

        struct PropertySchema: Encodable {
            let type: String
            let description: String

            static func normaliseType(_ raw: String) -> String {
                switch raw.lowercased() {
                case "string", "number", "integer", "boolean", "object", "array", "null":
                    return raw.lowercased()
                default:
                    return raw
                }
            }
        }
    }
}

private struct StreamUsage: Decodable {
    let promptTokens: Int
    let completionTokens: Int

    enum CodingKeys: String, CodingKey {
        case promptTokens     = "prompt_tokens"
        case completionTokens = "completion_tokens"
    }
}

private struct GenericStreamChunk: Decodable {
    struct Choice: Decodable {
        struct Delta: Decodable {
            let content: String?
        }
        let delta: Delta
    }
    let choices: [Choice]
    let usage: StreamUsage?
}

private struct GenericToolStreamChunk: Decodable {
    struct Choice: Decodable {
        struct Delta: Decodable {
            let content: String?
            let toolCalls: [ToolCallDelta]?

            enum CodingKeys: String, CodingKey {
                case content
                case toolCalls = "tool_calls"
            }
        }
        let delta: Delta
    }

    struct ToolCallDelta: Decodable {
        let index: Int
        let id: String?
        let function: FunctionDelta?
    }

    struct FunctionDelta: Decodable {
        let name: String?
        let arguments: String?
    }

    let choices: [Choice]
    let usage: StreamUsage?
}
