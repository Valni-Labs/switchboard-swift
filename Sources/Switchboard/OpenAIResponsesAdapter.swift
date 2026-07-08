import Foundation

public enum ReasoningEffort: String, Sendable, CaseIterable {
    case minimal
    case low
    case medium
    case high
}

@available(*, deprecated, message: "Use InferenceProvider; every model is served through POST /v1/switchboard/inference.")
public final class OpenAIResponsesAdapter: RawGenerationProvider, @unchecked Sendable {
    public let modelID: String

    public var endUserID: String?
    public var reasoningEffort: ReasoningEffort?

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
    private static let defaultMaxOutputTokens = 8_192
    private static let responsesPath = "responses"

    private let apiKey: String
    private let baseURL: URL
    private let urlSession: URLSession
    private let configuredContextWindow: Int?

    private var currentTask: Task<Void, Never>?

    public init(
        modelID: String,
        apiKey: String,
        endUserID: String? = nil,
        reasoningEffort: ReasoningEffort? = nil,
        baseURL: URL = OpenAIResponsesAdapter.defaultBaseURL,
        supportsVision: Bool = false,
        supportsTools: Bool = true,
        contextWindow: Int? = nil,
        urlSession: URLSession = .shared
    ) {
        self.modelID = modelID
        self.apiKey = apiKey
        self.endUserID = endUserID
        self.reasoningEffort = reasoningEffort
        self.supportsVision = supportsVision
        self.supportsTools = supportsTools
        self.configuredContextWindow = contextWindow
        let hostURL = baseURL.lastPathComponent == "v1"
            ? baseURL
            : baseURL.appendingPathComponent("v1")
        self.baseURL = hostURL
        self.urlSession = urlSession
    }

    public func generateRaw(messages: [ChatMessage]) -> AsyncThrowingStream<RawStreamChunk, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                self.lastUsage = nil
                do {
                    try self.refuseVisionWhenUnsupported(messages: messages)
                    for try await chunk in self.streamResponses(messages: messages, tools: []) {
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
                    for try await chunk in self.streamResponses(messages: messages, tools: tools) {
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

    private func streamResponses(
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
                        endUserID: endUserID,
                        reasoningEffort: reasoningEffort
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

                    var toolBuffers: [String: ToolCallBuffer] = [:]
                    var toolBufferOrder: [String] = []
                    var capturedInputTokens = 0
                    var capturedOutputTokens = 0

                    for try await line in bytes.lines {
                        try Task.checkCancellation()
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        if payload.isEmpty { continue }
                        guard payload != "[DONE]" else { break }
                        guard let data = payload.data(using: .utf8) else { continue }
                        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
                        let type = json["type"] as? String

                        switch type {
                        case "response.output_text.delta":
                            if let text = json["delta"] as? String, !text.isEmpty {
                                continuation.yield(.text(text))
                            }
                        case "response.output_item.added":
                            guard let item = json["item"] as? [String: Any],
                                  item["type"] as? String == "function_call",
                                  let itemID = item["id"] as? String,
                                  let callID = item["call_id"] as? String,
                                  let name = item["name"] as? String else { continue }
                            toolBuffers[itemID] = ToolCallBuffer(
                                callID: callID,
                                name: name,
                                arguments: item["arguments"] as? String ?? ""
                            )
                            toolBufferOrder.append(itemID)
                        case "response.function_call_arguments.delta":
                            guard let itemID = json["item_id"] as? String,
                                  let delta = json["delta"] as? String else { continue }
                            toolBuffers[itemID]?.arguments += delta
                        case "response.function_call_arguments.done":
                            guard let itemID = json["item_id"] as? String,
                                  let arguments = json["arguments"] as? String else { continue }
                            toolBuffers[itemID]?.arguments = arguments
                        case "response.completed", "response.incomplete":
                            if let responseObject = json["response"] as? [String: Any],
                               let usage = responseObject["usage"] as? [String: Any] {
                                capturedInputTokens = usage["input_tokens"] as? Int ?? capturedInputTokens
                                capturedOutputTokens = usage["output_tokens"] as? Int ?? capturedOutputTokens
                            }
                        default:
                            continue
                        }
                    }

                    for itemID in toolBufferOrder {
                        guard let buffer = toolBuffers[itemID] else { continue }
                        continuation.yield(.toolCall(
                            id: buffer.callID,
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
        let url = baseURL.appendingPathComponent(Self.responsesPath)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .useDefaultKeys
        request.httpBody = try encoder.encode(body)
        return request
    }

    static func buildRequestBody(
        messages: [ChatMessage],
        tools: [ToolSchema],
        modelID: String,
        endUserID: String?,
        reasoningEffort: ReasoningEffort?
    ) throws -> RequestBody {
        var items: [RequestBody.InputItem] = []
        for message in messages {
            switch message.role {
            case .system, .user:
                let parts = try inputParts(from: message.content, assistant: false)
                items.append(.message(role: message.role.rawValue, content: parts))
            case .assistant:
                let textParts = try inputParts(from: message.content, assistant: true)
                if textParts.contains(where: { if case .outputText(let text) = $0 { return !text.isEmpty } else { return false } }) {
                    items.append(.message(role: message.role.rawValue, content: textParts))
                }
                if let toolCalls = message.toolCalls {
                    for call in toolCalls {
                        items.append(.functionCall(
                            callID: call.id,
                            name: call.function.name,
                            arguments: call.function.arguments
                        ))
                    }
                }
            case .tool:
                guard let callID = message.toolCallID else {
                    throw ProviderError.requestInvalid(message: "tool-role message is missing its tool_call_id")
                }
                items.append(.functionCallOutput(callID: callID, output: flattenText(from: message.content)))
            }
        }

        let wireTools: [RequestBody.Tool]? = tools.isEmpty ? nil : tools.map { schema in
            RequestBody.Tool(
                name: schema.name,
                description: schema.description,
                parameters: responsesToolSchema(schema)
            )
        }

        return RequestBody(
            model: modelID,
            input: items,
            max_output_tokens: defaultMaxOutputTokens,
            stream: true,
            reasoning: reasoningEffort.map { RequestBody.Reasoning(effort: $0.rawValue) },
            tools: wireTools,
            user: endUserID
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

    private static func inputParts(from content: Content, assistant: Bool) throws -> [RequestBody.ContentPart] {
        switch content {
        case .text(let text):
            return [assistant ? .outputText(text) : .inputText(text)]
        case .blocks(let blocks):
            return blocks.map { block in
                switch block {
                case .text(let text):
                    return assistant ? .outputText(text) : .inputText(text)
                case .image(let image):
                    return .inputImage(dataURL: "data:\(image.mediaType);base64,\(image.base64)")
                }
            }
        }
    }

    private static func responsesToolSchema(_ schema: ToolSchema) -> JSONValue {
        var properties: [String: JSONValue] = [:]
        var required: [String] = []
        for parameter in schema.parameters {
            var fields: [String: JSONValue] = ["type": .string(parameter.type)]
            if !parameter.description.isEmpty {
                fields["description"] = .string(parameter.description)
            }
            properties[parameter.name] = .object(fields)
            if parameter.required {
                required.append(parameter.name)
            }
        }
        return .object([
            "type": .string("object"),
            "properties": .object(properties),
            "required": .array(required.map { .string($0) }),
        ])
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
        let input: [InputItem]
        let max_output_tokens: Int
        let stream: Bool
        let reasoning: Reasoning?
        let tools: [Tool]?
        let user: String?

        struct Reasoning: Encodable {
            let effort: String
        }

        struct Tool: Encodable {
            let type = "function"
            let name: String
            let description: String
            let parameters: JSONValue
        }

        enum InputItem: Encodable {
            case message(role: String, content: [ContentPart])
            case functionCall(callID: String, name: String, arguments: String)
            case functionCallOutput(callID: String, output: String)

            enum CodingKeys: String, CodingKey {
                case type, role, content, name, arguments, output
                case callID = "call_id"
            }

            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                switch self {
                case .message(let role, let content):
                    try container.encode("message", forKey: .type)
                    try container.encode(role, forKey: .role)
                    try container.encode(content, forKey: .content)
                case .functionCall(let callID, let name, let arguments):
                    try container.encode("function_call", forKey: .type)
                    try container.encode(callID, forKey: .callID)
                    try container.encode(name, forKey: .name)
                    try container.encode(arguments, forKey: .arguments)
                case .functionCallOutput(let callID, let output):
                    try container.encode("function_call_output", forKey: .type)
                    try container.encode(callID, forKey: .callID)
                    try container.encode(output, forKey: .output)
                }
            }
        }

        enum ContentPart: Encodable {
            case inputText(String)
            case inputImage(dataURL: String)
            case outputText(String)

            enum CodingKeys: String, CodingKey {
                case type, text
                case imageURL = "image_url"
            }

            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                switch self {
                case .inputText(let text):
                    try container.encode("input_text", forKey: .type)
                    try container.encode(text, forKey: .text)
                case .inputImage(let dataURL):
                    try container.encode("input_image", forKey: .type)
                    try container.encode(dataURL, forKey: .imageURL)
                case .outputText(let text):
                    try container.encode("output_text", forKey: .type)
                    try container.encode(text, forKey: .text)
                }
            }
        }
    }

    private struct ToolCallBuffer {
        var callID: String
        var name: String
        var arguments: String
    }
}
