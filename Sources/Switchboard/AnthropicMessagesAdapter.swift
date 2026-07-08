import Foundation

@available(*, deprecated, message: "Use InferenceProvider; every model is served through POST /v1/switchboard/inference.")
public final class AnthropicMessagesAdapter: RawGenerationProvider, @unchecked Sendable {
    public let modelID: String

    public var endUserID: String?

    public let supportsVision: Bool
    public let supportsTools: Bool
    public private(set) var lastUsage: GenerationUsage?

    public var contextLimits: ModelLimits {
        guard let window = configuredContextWindow else { return .remoteDefault }
        return ModelLimits(contextWindow: window, budgetTokens: ModelLimits.remoteDefault.budgetTokens)
    }
    public var preferredToolCallMode: ToolCallMode { supportsTools ? .native : .prompt }

    public static let defaultBaseURL = URL(string: "https://switchboard.valni.app/v1")!

    private static let maxErrorBodyBytes = 64 * 1024
    private static let defaultMaxTokens = 8_192
    private static let messagesPath = "/v1/messages"
    private static let anthropicVersion = "2023-06-01"

    private let apiKey: String
    private let baseURL: URL
    private let urlSession: URLSession
    private let configuredContextWindow: Int?

    private var currentTask: Task<Void, Never>?

    public init(
        modelID: String,
        apiKey: String,
        endUserID: String? = nil,
        baseURL: URL = AnthropicMessagesAdapter.defaultBaseURL,
        supportsVision: Bool = false,
        supportsTools: Bool = true,
        contextWindow: Int? = nil,
        urlSession: URLSession = .shared
    ) {
        self.modelID = modelID
        self.apiKey = apiKey
        self.endUserID = endUserID
        self.supportsVision = supportsVision
        self.supportsTools = supportsTools
        self.configuredContextWindow = contextWindow
        let hostURL = baseURL.lastPathComponent == "v1"
            ? baseURL.deletingLastPathComponent()
            : baseURL
        self.baseURL = hostURL
        self.urlSession = urlSession
    }

    public func generateRaw(messages: [ChatMessage]) -> AsyncThrowingStream<RawStreamChunk, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                self.lastUsage = nil
                do {
                    try self.refuseVisionWhenUnsupported(messages: messages)
                    for try await chunk in self.streamMessages(messages: messages, tools: []) {
                        try Task.checkCancellation()
                        switch chunk {
                        case .text(let text):
                            continuation.yield(.text(text))
                        case .toolCall:
                            continue
                        case .paywall(let event):
                            continuation.yield(.paywall(event))
                        }
                    }
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
                do {
                    try self.refuseVisionWhenUnsupported(messages: messages)
                    for try await chunk in self.streamMessages(messages: messages, tools: tools) {
                        try Task.checkCancellation()
                        continuation.yield(chunk)
                    }
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

    private func refuseVisionWhenUnsupported(messages: [ChatMessage]) throws {
        if !supportsVision, messages.contains(where: \.hasNonTextContent) {
            throw RoutingError.imagesNotSupportedByModel(modelID: modelID)
        }
    }

    private func streamMessages(
        messages: [ChatMessage],
        tools: [ToolSchema]
    ) -> AsyncThrowingStream<NativeStreamChunk, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let requestBody = try Self.buildRequestBody(
                        messages: messages,
                        tools: tools,
                        modelID: modelID,
                        endUserID: endUserID
                    )
                    let request = try self.buildURLRequest(body: requestBody)
                    let (bytes, response) = try await self.urlSession.bytes(for: request)

                    if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                        var collected = Data()
                        for try await byte in bytes {
                            collected.append(byte)
                            if collected.count > Self.maxErrorBodyBytes { break }
                        }
                        throw Self.mapHTTPError(status: http.statusCode, body: collected)
                    }

                    var toolBuffers: [Int: ToolCallBuffer] = [:]
                    var capturedInputTokens = 0
                    var capturedOutputTokens = 0

                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        if payload.isEmpty { continue }
                        guard let data = payload.data(using: .utf8) else { continue }
                        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                        let type = json["type"] as? String

                        switch type {
                        case "message_start":
                            if let msg = json["message"] as? [String: Any],
                               let usage = msg["usage"] as? [String: Any],
                               let input = usage["input_tokens"] as? Int {
                                capturedInputTokens = input
                            }
                        case "content_block_start":
                            guard let index = json["index"] as? Int,
                                  let block = json["content_block"] as? [String: Any],
                                  block["type"] as? String == "tool_use",
                                  let id = block["id"] as? String,
                                  let name = block["name"] as? String else { continue }
                            toolBuffers[index] = ToolCallBuffer(id: id, name: name, arguments: "")
                        case "content_block_delta":
                            guard let index = json["index"] as? Int,
                                  let delta = json["delta"] as? [String: Any],
                                  let deltaType = delta["type"] as? String else { continue }
                            if deltaType == "text_delta", let text = delta["text"] as? String, !text.isEmpty {
                                continuation.yield(.text(text))
                            } else if deltaType == "input_json_delta", let partial = delta["partial_json"] as? String {
                                toolBuffers[index]?.arguments += partial
                            }
                        case "message_delta":
                            if let usage = json["usage"] as? [String: Any],
                               let output = usage["output_tokens"] as? Int {
                                capturedOutputTokens = output
                            }
                        case "message_stop", "content_block_stop", "ping":
                            continue
                        default:
                            continue
                        }
                    }

                    for index in toolBuffers.keys.sorted() {
                        let buffer = toolBuffers[index]!
                        continuation.yield(.toolCall(
                            id: buffer.id,
                            name: buffer.name,
                            argumentsJSON: buffer.arguments
                        ))
                    }
                    if capturedInputTokens > 0 || capturedOutputTokens > 0 {
                        self.lastUsage = GenerationUsage(
                            inputTokens: capturedInputTokens,
                            outputTokens: capturedOutputTokens
                        )
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func buildURLRequest(body: RequestBody) throws -> URLRequest {
        let url = baseURL.appendingPathComponent(Self.messagesPath.trimmingCharacters(in: CharacterSet(charactersIn: "/")))
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(Self.anthropicVersion, forHTTPHeaderField: "anthropic-version")
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .useDefaultKeys
        request.httpBody = try encoder.encode(body)
        return request
    }

    static func buildRequestBody(
        messages: [ChatMessage],
        tools: [ToolSchema],
        modelID: String,
        endUserID: String?
    ) throws -> RequestBody {
        var systemText: String?
        var wireMessages: [RequestBody.Message] = []
        for message in messages {
            switch message.role {
            case .system:
                let text = flattenText(from: message.content)
                if !text.isEmpty {
                    systemText = (systemText.map { $0 + "\n" } ?? "") + text
                }
            case .user:
                let blocks = try wireBlocks(from: message.content)
                wireMessages.append(RequestBody.Message(role: message.role.rawValue, content: blocks))
            case .assistant:
                var blocks = try wireBlocks(from: message.content)
                if let toolCalls = message.toolCalls {
                    blocks.removeAll { block in
                        if case .text(let text) = block { return text.isEmpty }
                        return false
                    }
                    for call in toolCalls {
                        blocks.append(.toolUse(
                            id: call.id,
                            name: call.function.name,
                            input: try JSONValue(parsingObject: call.function.arguments, context: "tool call '\(call.function.name)' arguments")
                        ))
                    }
                }
                wireMessages.append(RequestBody.Message(role: message.role.rawValue, content: blocks))
            case .tool:
                guard let callID = message.toolCallID else {
                    throw ProviderError.requestInvalid(message: "tool-role message is missing its tool_call_id")
                }
                let resultBlock = RequestBody.ContentBlock.toolResult(
                    toolUseID: callID,
                    content: flattenText(from: message.content)
                )
                if let last = wireMessages.last, last.role == ChatMessage.Role.user.rawValue,
                   last.content.contains(where: \.isToolResult) {
                    wireMessages[wireMessages.count - 1].content.append(resultBlock)
                } else {
                    wireMessages.append(RequestBody.Message(role: ChatMessage.Role.user.rawValue, content: [resultBlock]))
                }
            }
        }

        let wireTools: [RequestBody.Tool]? = tools.isEmpty ? nil : tools.map { schema in
            RequestBody.Tool(
                name: schema.name,
                description: schema.description,
                input_schema: schema.jsonSchema()
            )
        }

        let metadata = endUserID.map { RequestBody.Metadata(user_id: $0) }

        if let lastMessageIndex = wireMessages.indices.last,
           let lastBlockIndex = wireMessages[lastMessageIndex].content.indices.last {
            let lastBlock = wireMessages[lastMessageIndex].content[lastBlockIndex]
            wireMessages[lastMessageIndex].content[lastBlockIndex] = .cached(lastBlock)
        }

        return RequestBody(
            model: modelID,
            messages: wireMessages,
            system: systemText.map { [RequestBody.SystemBlock(text: $0, cache_control: RequestBody.CacheControl())] },
            max_tokens: defaultMaxTokens,
            stream: true,
            tools: wireTools,
            metadata: metadata
        )
    }

    private static func flattenText(from content: Content) -> String {
        switch content {
        case .text(let text):
            return text
        case .blocks(let blocks):
            return blocks.compactMap { block -> String? in
                if case .text(let text) = block { return text }
                return nil
            }.joined(separator: "\n")
        }
    }

    private static func wireBlocks(from content: Content) throws -> [RequestBody.ContentBlock] {
        switch content {
        case .text(let text):
            return [.text(text)]
        case .blocks(let blocks):
            return try blocks.map { block in
                switch block {
                case .text(let text):
                    return .text(text)
                case .image(let image):
                    return .image(mediaType: image.mediaType, base64: image.base64)
                }
            }
        }
    }

    static func mapHTTPError(status: Int, body: Data) -> ProviderError {
        let text = String(data: body, encoding: .utf8) ?? ""
        if let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
           let code = json["code"] as? String {
            let message = (json["error"] as? String) ?? text
            let envelope = ErrorEnvelope(
                code: code,
                error: message,
                model: json["model"] as? String,
                provider: json["provider"] as? String,
                spentMicros: json["spentMicros"] as? Int,
                capMicros: json["capMicros"] as? Int,
                retryAfterSeconds: json["retryAfterSeconds"] as? Int
            )
            return SwitchboardProvider.mapError(status: status, envelope: envelope, rawBody: body)
        }
        return .serverError(status: status, code: nil, message: text.isEmpty ? "Empty body" : String(text.prefix(256)))
    }

    struct RequestBody: Encodable {
        let model: String
        let messages: [Message]
        let system: [SystemBlock]?
        let max_tokens: Int
        let stream: Bool
        let tools: [Tool]?
        let metadata: Metadata?

        struct CacheControl: Encodable {
            let type = "ephemeral"
        }

        struct SystemBlock: Encodable {
            let type = "text"
            let text: String
            let cache_control: CacheControl?
        }

        struct Message: Encodable {
            let role: String
            var content: [ContentBlock]
        }

        indirect enum ContentBlock: Encodable {
            case text(String)
            case image(mediaType: String, base64: String)
            case toolUse(id: String, name: String, input: JSONValue)
            case toolResult(toolUseID: String, content: String)
            case cached(ContentBlock)

            var isToolResult: Bool {
                if case .toolResult = self { return true }
                if case .cached(let inner) = self { return inner.isToolResult }
                return false
            }

            enum CodingKeys: String, CodingKey {
                case type, text, source, id, name, input, content
                case toolUseID = "tool_use_id"
                case cacheControl = "cache_control"
            }

            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                switch self {
                case .cached(let inner):
                    try inner.encode(to: encoder)
                    try container.encode(CacheControl(), forKey: .cacheControl)
                case .text(let text):
                    try container.encode("text", forKey: .type)
                    try container.encode(text, forKey: .text)
                case .image(let mediaType, let base64):
                    try container.encode("image", forKey: .type)
                    try container.encode(
                        ImageSource(type: "base64", media_type: mediaType, data: base64),
                        forKey: .source
                    )
                case .toolUse(let id, let name, let input):
                    try container.encode("tool_use", forKey: .type)
                    try container.encode(id, forKey: .id)
                    try container.encode(name, forKey: .name)
                    try container.encode(input, forKey: .input)
                case .toolResult(let toolUseID, let content):
                    try container.encode("tool_result", forKey: .type)
                    try container.encode(toolUseID, forKey: .toolUseID)
                    try container.encode(content, forKey: .content)
                }
            }

            struct ImageSource: Encodable {
                let type: String
                let media_type: String
                let data: String
            }
        }

        struct Tool: Encodable {
            let name: String
            let description: String
            let input_schema: JSONValue
        }

        struct Metadata: Encodable {
            let user_id: String
        }
    }

    private struct ToolCallBuffer {
        var id: String
        var name: String
        var arguments: String
    }
}

private extension ToolSchema {
    func jsonSchema() -> JSONValue {
        var properties: [String: JSONValue] = [:]
        var required: [String] = []
        for param in parameters {
            properties[param.name] = param.jsonSchemaObject()
            if param.required {
                required.append(param.name)
            }
        }
        return .object([
            "type": .string("object"),
            "properties": .object(properties),
            "required": .array(required.map { .string($0) }),
        ])
    }
}

private extension ToolParameter {
    func jsonSchemaObject() -> JSONValue {
        var fields: [String: JSONValue] = [
            "type": .string(type),
        ]
        if !description.isEmpty {
            fields["description"] = .string(description)
        }
        return .object(fields)
    }
}

indirect enum JSONValue: Encodable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    init(parsingObject json: String, context: String) throws {
        guard let data = json.data(using: .utf8),
              let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ProviderError.requestInvalid(message: "\(context) were not a valid JSON object")
        }
        self = Self.fromFoundation(parsed)
    }

    private static func fromFoundation(_ value: Any) -> JSONValue {
        switch value {
        case let dictionary as [String: Any]:
            return .object(dictionary.mapValues(fromFoundation))
        case let array as [Any]:
            return .array(array.map(fromFoundation))
        case let string as String:
            return .string(string)
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return .bool(number.boolValue)
            }
            return .number(number.doubleValue)
        default:
            return .null
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:              try container.encodeNil()
        case .bool(let value):   try container.encode(value)
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value):  try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }
}
