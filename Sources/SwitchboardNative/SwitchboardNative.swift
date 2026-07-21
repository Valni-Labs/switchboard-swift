import Foundation

public struct SwitchboardRouter: Codable, Sendable {
    public var userId: String
    public var time: String
    public var idempotencyKey: String
    public var kind: RouterBody

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
        case time
        case idempotencyKey = "idempotency_key"
        case kind
    }

    public init(userId: String, time: String, idempotencyKey: String, kind: RouterBody) {
        self.userId = userId
        self.time = time
        self.idempotencyKey = idempotencyKey
        self.kind = kind
    }
}

public enum RouterBody: Codable, Sendable {
    case anthropic(AnthropicMessagesRequest)
    case openaiPro(OpenAIResponsesRequest)
    case openaiGeneric(OpenAIChatRequest)
    case google(GoogleGenerateContentRequest)
    case unrecognized(String)

    private enum CodingKeys: String, CodingKey {
        case anthropic = "anthropic"
        case openaiPro = "openai_pro"
        case openaiGeneric = "openai_generic"
        case google = "google"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let value = try container.decodeIfPresent(AnthropicMessagesRequest.self, forKey: .anthropic) {
            self = .anthropic(value); return
        }
        if let value = try container.decodeIfPresent(OpenAIResponsesRequest.self, forKey: .openaiPro) {
            self = .openaiPro(value); return
        }
        if let value = try container.decodeIfPresent(OpenAIChatRequest.self, forKey: .openaiGeneric) {
            self = .openaiGeneric(value); return
        }
        if let value = try container.decodeIfPresent(GoogleGenerateContentRequest.self, forKey: .google) {
            self = .google(value); return
        }
        let raw = try decoder.singleValueContainer().decode([String: SwitchboardJSON].self)
        self = .unrecognized(raw.keys.sorted().first ?? "")
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .anthropic(let value): try container.encode(value, forKey: .anthropic)
        case .openaiPro(let value): try container.encode(value, forKey: .openaiPro)
        case .openaiGeneric(let value): try container.encode(value, forKey: .openaiGeneric)
        case .google(let value): try container.encode(value, forKey: .google)
        case .unrecognized:
            throw EncodingError.invalidValue(self, EncodingError.Context(codingPath: encoder.codingPath, debugDescription: "Cannot encode an unrecognized RouterBody tag"))
        }
    }
}

public struct AnthropicCacheControl: Codable, Sendable {
    public var type: String
    public var ttl: String?

    public init(type: String, ttl: String? = nil) {
        self.type = type
        self.ttl = ttl
    }
}

public struct AnthropicImageSource: Codable, Sendable {
    public var type: AnthropicImageSourceType
    public var mediaType: String?
    public var data: String?
    public var url: String?

    enum CodingKeys: String, CodingKey {
        case type
        case mediaType = "media_type"
        case data
        case url
    }

    public init(type: AnthropicImageSourceType, mediaType: String? = nil, data: String? = nil, url: String? = nil) {
        self.type = type
        self.mediaType = mediaType
        self.data = data
        self.url = url
    }
}

public enum AnthropicImageSourceType: String, Codable, Sendable {
    case base64
    case url
}

public enum AnthropicContentBlock: Codable, Sendable {
    case text(AnthropicContentBlockText)
    case image(AnthropicContentBlockImage)
    case toolUse(AnthropicContentBlockToolUse)
    case toolResult(AnthropicContentBlockToolResult)
    case thinking(AnthropicContentBlockThinking)
    case unrecognized(String)

    private enum DiscriminatorKeys: String, CodingKey { case discriminator = "type" }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DiscriminatorKeys.self)
        let discriminator = try container.decode(String.self, forKey: .discriminator)
        switch discriminator {
        case "text": self = .text(try AnthropicContentBlockText(from: decoder))
        case "image": self = .image(try AnthropicContentBlockImage(from: decoder))
        case "tool_use": self = .toolUse(try AnthropicContentBlockToolUse(from: decoder))
        case "tool_result": self = .toolResult(try AnthropicContentBlockToolResult(from: decoder))
        case "thinking": self = .thinking(try AnthropicContentBlockThinking(from: decoder))
        default: self = .unrecognized(discriminator)
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .text(let value): try value.encode(to: encoder)
        case .image(let value): try value.encode(to: encoder)
        case .toolUse(let value): try value.encode(to: encoder)
        case .toolResult(let value): try value.encode(to: encoder)
        case .thinking(let value): try value.encode(to: encoder)
        case .unrecognized(let discriminator):
            var container = encoder.container(keyedBy: DiscriminatorKeys.self)
            try container.encode(discriminator, forKey: .discriminator)
        }
    }
}

public struct AnthropicContentBlockText: Codable, Sendable {
    public var type: String
    public var text: String
    public var cacheControl: AnthropicCacheControl?

    enum CodingKeys: String, CodingKey {
        case type
        case text
        case cacheControl = "cache_control"
    }

    public init(type: String, text: String, cacheControl: AnthropicCacheControl? = nil) {
        self.type = type
        self.text = text
        self.cacheControl = cacheControl
    }
}

public struct AnthropicContentBlockImage: Codable, Sendable {
    public var type: String
    public var source: AnthropicImageSource
    public var cacheControl: AnthropicCacheControl?

    enum CodingKeys: String, CodingKey {
        case type
        case source
        case cacheControl = "cache_control"
    }

    public init(type: String, source: AnthropicImageSource, cacheControl: AnthropicCacheControl? = nil) {
        self.type = type
        self.source = source
        self.cacheControl = cacheControl
    }
}

public struct AnthropicContentBlockToolUse: Codable, Sendable {
    public var type: String
    public var id: String
    public var name: String
    public var input: SwitchboardJSON
    public var cacheControl: AnthropicCacheControl?

    enum CodingKeys: String, CodingKey {
        case type
        case id
        case name
        case input
        case cacheControl = "cache_control"
    }

    public init(type: String, id: String, name: String, input: SwitchboardJSON, cacheControl: AnthropicCacheControl? = nil) {
        self.type = type
        self.id = id
        self.name = name
        self.input = input
        self.cacheControl = cacheControl
    }
}

public struct AnthropicContentBlockToolResult: Codable, Sendable {
    public var type: String
    public var toolUseId: String
    public var content: SwitchboardJSON
    public var isError: Bool?
    public var cacheControl: AnthropicCacheControl?

    enum CodingKeys: String, CodingKey {
        case type
        case toolUseId = "tool_use_id"
        case content
        case isError = "is_error"
        case cacheControl = "cache_control"
    }

    public init(type: String, toolUseId: String, content: SwitchboardJSON, isError: Bool? = nil, cacheControl: AnthropicCacheControl? = nil) {
        self.type = type
        self.toolUseId = toolUseId
        self.content = content
        self.isError = isError
        self.cacheControl = cacheControl
    }
}

public struct AnthropicContentBlockThinking: Codable, Sendable {
    public var type: String
    public var thinking: String
    public var signature: String

    public init(type: String, thinking: String, signature: String) {
        self.type = type
        self.thinking = thinking
        self.signature = signature
    }
}

public struct AnthropicMessage: Codable, Sendable {
    public var role: AnthropicMessageRole
    public var content: SwitchboardJSON

    public init(role: AnthropicMessageRole, content: SwitchboardJSON) {
        self.role = role
        self.content = content
    }
}

public enum AnthropicMessageRole: String, Codable, Sendable {
    case user
    case assistant
}

public struct AnthropicSystemBlock: Codable, Sendable {
    public var type: String
    public var text: String
    public var cacheControl: AnthropicCacheControl?

    enum CodingKeys: String, CodingKey {
        case type
        case text
        case cacheControl = "cache_control"
    }

    public init(type: String, text: String, cacheControl: AnthropicCacheControl? = nil) {
        self.type = type
        self.text = text
        self.cacheControl = cacheControl
    }
}

public enum AnthropicSystem: Codable, Sendable {
    case text(String)
    case blocks([AnthropicSystemBlock])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(String.self) { self = .text(value); return }
        self = .blocks(try container.decode([AnthropicSystemBlock].self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .text(let value): try container.encode(value)
        case .blocks(let value): try container.encode(value)
        }
    }
}

public struct AnthropicTool: Codable, Sendable {
    public var name: String
    public var description: String?
    public var inputSchema: SwitchboardJSON
    public var cacheControl: AnthropicCacheControl?

    enum CodingKeys: String, CodingKey {
        case name
        case description
        case inputSchema = "input_schema"
        case cacheControl = "cache_control"
    }

    public init(name: String, description: String? = nil, inputSchema: SwitchboardJSON, cacheControl: AnthropicCacheControl? = nil) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
        self.cacheControl = cacheControl
    }
}

public enum AnthropicToolChoice: Codable, Sendable {
    case auto(AnthropicToolChoiceAuto)
    case any(AnthropicToolChoiceAny)
    case `none`(AnthropicToolChoiceNone)
    case tool(AnthropicToolChoiceTool)
    case unrecognized(String)

    private enum DiscriminatorKeys: String, CodingKey { case discriminator = "type" }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DiscriminatorKeys.self)
        let discriminator = try container.decode(String.self, forKey: .discriminator)
        switch discriminator {
        case "auto": self = .auto(try AnthropicToolChoiceAuto(from: decoder))
        case "any": self = .any(try AnthropicToolChoiceAny(from: decoder))
        case "none": self = .`none`(try AnthropicToolChoiceNone(from: decoder))
        case "tool": self = .tool(try AnthropicToolChoiceTool(from: decoder))
        default: self = .unrecognized(discriminator)
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .auto(let value): try value.encode(to: encoder)
        case .any(let value): try value.encode(to: encoder)
        case .`none`(let value): try value.encode(to: encoder)
        case .tool(let value): try value.encode(to: encoder)
        case .unrecognized(let discriminator):
            var container = encoder.container(keyedBy: DiscriminatorKeys.self)
            try container.encode(discriminator, forKey: .discriminator)
        }
    }
}

public struct AnthropicToolChoiceAuto: Codable, Sendable {
    public var type: String

    public init(type: String) {
        self.type = type
    }
}

public struct AnthropicToolChoiceAny: Codable, Sendable {
    public var type: String

    public init(type: String) {
        self.type = type
    }
}

public struct AnthropicToolChoiceNone: Codable, Sendable {
    public var type: String

    public init(type: String) {
        self.type = type
    }
}

public struct AnthropicToolChoiceTool: Codable, Sendable {
    public var type: String
    public var name: String

    public init(type: String, name: String) {
        self.type = type
        self.name = name
    }
}

public enum AnthropicThinking: Codable, Sendable {
    case adaptive(AnthropicThinkingAdaptive)
    case enabled(AnthropicThinkingEnabled)
    case disabled(AnthropicThinkingDisabled)
    case unrecognized(String)

    private enum DiscriminatorKeys: String, CodingKey { case discriminator = "type" }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DiscriminatorKeys.self)
        let discriminator = try container.decode(String.self, forKey: .discriminator)
        switch discriminator {
        case "adaptive": self = .adaptive(try AnthropicThinkingAdaptive(from: decoder))
        case "enabled": self = .enabled(try AnthropicThinkingEnabled(from: decoder))
        case "disabled": self = .disabled(try AnthropicThinkingDisabled(from: decoder))
        default: self = .unrecognized(discriminator)
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .adaptive(let value): try value.encode(to: encoder)
        case .enabled(let value): try value.encode(to: encoder)
        case .disabled(let value): try value.encode(to: encoder)
        case .unrecognized(let discriminator):
            var container = encoder.container(keyedBy: DiscriminatorKeys.self)
            try container.encode(discriminator, forKey: .discriminator)
        }
    }
}

public struct AnthropicThinkingAdaptive: Codable, Sendable {
    public var type: String
    public var display: AnthropicThinkingAdaptiveDisplay?

    public init(type: String, display: AnthropicThinkingAdaptiveDisplay? = nil) {
        self.type = type
        self.display = display
    }
}

public struct AnthropicThinkingEnabled: Codable, Sendable {
    public var type: String
    public var budgetTokens: Double

    enum CodingKeys: String, CodingKey {
        case type
        case budgetTokens = "budget_tokens"
    }

    public init(type: String, budgetTokens: Double) {
        self.type = type
        self.budgetTokens = budgetTokens
    }
}

public struct AnthropicThinkingDisabled: Codable, Sendable {
    public var type: String

    public init(type: String) {
        self.type = type
    }
}

public enum AnthropicThinkingAdaptiveDisplay: String, Codable, Sendable {
    case summarized
    case omitted
}

public enum AnthropicEffort: String, Codable, Sendable {
    case low
    case medium
    case high
    case xhigh
    case max
}

public struct AnthropicOutputFormat: Codable, Sendable {
    public var type: String
    public var schema: SwitchboardJSON

    public init(type: String, schema: SwitchboardJSON) {
        self.type = type
        self.schema = schema
    }
}

public struct AnthropicOutputConfig: Codable, Sendable {
    public var effort: AnthropicEffort?
    public var format: AnthropicOutputFormat?

    public init(effort: AnthropicEffort? = nil, format: AnthropicOutputFormat? = nil) {
        self.effort = effort
        self.format = format
    }
}

public struct AnthropicMetadata: Codable, Sendable {
    public var userId: String?

    enum CodingKeys: String, CodingKey {
        case userId = "user_id"
    }

    public init(userId: String? = nil) {
        self.userId = userId
    }
}

public struct AnthropicMessagesRequest: Codable, Sendable {
    public var model: String
    public var messages: [AnthropicMessage]
    public var maxTokens: Double
    public var system: AnthropicSystem?
    public var temperature: Double?
    public var topP: Double?
    public var topK: Double?
    public var stopSequences: [String]?
    public var stream: Bool?
    public var tools: [AnthropicTool]?
    public var toolChoice: AnthropicToolChoice?
    public var thinking: AnthropicThinking?
    public var outputConfig: AnthropicOutputConfig?
    public var metadata: AnthropicMetadata?

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case maxTokens = "max_tokens"
        case system
        case temperature
        case topP = "top_p"
        case topK = "top_k"
        case stopSequences = "stop_sequences"
        case stream
        case tools
        case toolChoice = "tool_choice"
        case thinking
        case outputConfig = "output_config"
        case metadata
    }

    public init(model: String, messages: [AnthropicMessage], maxTokens: Double, system: AnthropicSystem? = nil, temperature: Double? = nil, topP: Double? = nil, topK: Double? = nil, stopSequences: [String]? = nil, stream: Bool? = nil, tools: [AnthropicTool]? = nil, toolChoice: AnthropicToolChoice? = nil, thinking: AnthropicThinking? = nil, outputConfig: AnthropicOutputConfig? = nil, metadata: AnthropicMetadata? = nil) {
        self.model = model
        self.messages = messages
        self.maxTokens = maxTokens
        self.system = system
        self.temperature = temperature
        self.topP = topP
        self.topK = topK
        self.stopSequences = stopSequences
        self.stream = stream
        self.tools = tools
        self.toolChoice = toolChoice
        self.thinking = thinking
        self.outputConfig = outputConfig
        self.metadata = metadata
    }
}

public struct AnthropicUsage: Codable, Sendable {
    public var inputTokens: Double
    public var outputTokens: Double
    public var cacheCreationInputTokens: Double?
    public var cacheReadInputTokens: Double?

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case cacheCreationInputTokens = "cache_creation_input_tokens"
        case cacheReadInputTokens = "cache_read_input_tokens"
    }

    public init(inputTokens: Double, outputTokens: Double, cacheCreationInputTokens: Double? = nil, cacheReadInputTokens: Double? = nil) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.cacheCreationInputTokens = cacheCreationInputTokens
        self.cacheReadInputTokens = cacheReadInputTokens
    }
}

public enum AnthropicResponseContentBlock: Codable, Sendable {
    case text(AnthropicResponseContentBlockText)
    case toolUse(AnthropicResponseContentBlockToolUse)
    case thinking(AnthropicResponseContentBlockThinking)
    case unrecognized(String)

    private enum DiscriminatorKeys: String, CodingKey { case discriminator = "type" }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DiscriminatorKeys.self)
        let discriminator = try container.decode(String.self, forKey: .discriminator)
        switch discriminator {
        case "text": self = .text(try AnthropicResponseContentBlockText(from: decoder))
        case "tool_use": self = .toolUse(try AnthropicResponseContentBlockToolUse(from: decoder))
        case "thinking": self = .thinking(try AnthropicResponseContentBlockThinking(from: decoder))
        default: self = .unrecognized(discriminator)
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .text(let value): try value.encode(to: encoder)
        case .toolUse(let value): try value.encode(to: encoder)
        case .thinking(let value): try value.encode(to: encoder)
        case .unrecognized(let discriminator):
            var container = encoder.container(keyedBy: DiscriminatorKeys.self)
            try container.encode(discriminator, forKey: .discriminator)
        }
    }
}

public struct AnthropicResponseContentBlockText: Codable, Sendable {
    public var type: String
    public var text: String

    public init(type: String, text: String) {
        self.type = type
        self.text = text
    }
}

public struct AnthropicResponseContentBlockToolUse: Codable, Sendable {
    public var type: String
    public var id: String
    public var name: String
    public var input: SwitchboardJSON

    public init(type: String, id: String, name: String, input: SwitchboardJSON) {
        self.type = type
        self.id = id
        self.name = name
        self.input = input
    }
}

public struct AnthropicResponseContentBlockThinking: Codable, Sendable {
    public var type: String
    public var thinking: String
    public var signature: String

    public init(type: String, thinking: String, signature: String) {
        self.type = type
        self.thinking = thinking
        self.signature = signature
    }
}

public struct AnthropicMessageResponse: Codable, Sendable {
    public var id: String
    public var type: String
    public var role: String
    public var model: String
    public var content: [AnthropicResponseContentBlock]
    public var stopReason: AnthropicMessageResponseStopReason?
    public var stopSequence: String?
    public var usage: AnthropicUsage

    enum CodingKeys: String, CodingKey {
        case id
        case type
        case role
        case model
        case content
        case stopReason = "stop_reason"
        case stopSequence = "stop_sequence"
        case usage
    }

    public init(id: String, type: String, role: String, model: String, content: [AnthropicResponseContentBlock], stopReason: AnthropicMessageResponseStopReason? = nil, stopSequence: String? = nil, usage: AnthropicUsage) {
        self.id = id
        self.type = type
        self.role = role
        self.model = model
        self.content = content
        self.stopReason = stopReason
        self.stopSequence = stopSequence
        self.usage = usage
    }
}

public enum AnthropicMessageResponseStopReason: String, Codable, Sendable {
    case endTurn = "end_turn"
    case maxTokens = "max_tokens"
    case stopSequence = "stop_sequence"
    case toolUse = "tool_use"
    case pauseTurn = "pause_turn"
    case refusal
}

public enum AnthropicBlockDelta: Codable, Sendable {
    case textDelta(AnthropicBlockDeltaTextDelta)
    case inputJsonDelta(AnthropicBlockDeltaInputJsonDelta)
    case thinkingDelta(AnthropicBlockDeltaThinkingDelta)
    case signatureDelta(AnthropicBlockDeltaSignatureDelta)
    case unrecognized(String)

    private enum DiscriminatorKeys: String, CodingKey { case discriminator = "type" }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DiscriminatorKeys.self)
        let discriminator = try container.decode(String.self, forKey: .discriminator)
        switch discriminator {
        case "text_delta": self = .textDelta(try AnthropicBlockDeltaTextDelta(from: decoder))
        case "input_json_delta": self = .inputJsonDelta(try AnthropicBlockDeltaInputJsonDelta(from: decoder))
        case "thinking_delta": self = .thinkingDelta(try AnthropicBlockDeltaThinkingDelta(from: decoder))
        case "signature_delta": self = .signatureDelta(try AnthropicBlockDeltaSignatureDelta(from: decoder))
        default: self = .unrecognized(discriminator)
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .textDelta(let value): try value.encode(to: encoder)
        case .inputJsonDelta(let value): try value.encode(to: encoder)
        case .thinkingDelta(let value): try value.encode(to: encoder)
        case .signatureDelta(let value): try value.encode(to: encoder)
        case .unrecognized(let discriminator):
            var container = encoder.container(keyedBy: DiscriminatorKeys.self)
            try container.encode(discriminator, forKey: .discriminator)
        }
    }
}

public struct AnthropicBlockDeltaTextDelta: Codable, Sendable {
    public var type: String
    public var text: String

    public init(type: String, text: String) {
        self.type = type
        self.text = text
    }
}

public struct AnthropicBlockDeltaInputJsonDelta: Codable, Sendable {
    public var type: String
    public var partialJson: String

    enum CodingKeys: String, CodingKey {
        case type
        case partialJson = "partial_json"
    }

    public init(type: String, partialJson: String) {
        self.type = type
        self.partialJson = partialJson
    }
}

public struct AnthropicBlockDeltaThinkingDelta: Codable, Sendable {
    public var type: String
    public var thinking: String

    public init(type: String, thinking: String) {
        self.type = type
        self.thinking = thinking
    }
}

public struct AnthropicBlockDeltaSignatureDelta: Codable, Sendable {
    public var type: String
    public var signature: String

    public init(type: String, signature: String) {
        self.type = type
        self.signature = signature
    }
}

public enum AnthropicStreamEvent: Codable, Sendable {
    case messageStart(AnthropicStreamEventMessageStart)
    case contentBlockStart(AnthropicStreamEventContentBlockStart)
    case contentBlockDelta(AnthropicStreamEventContentBlockDelta)
    case contentBlockStop(AnthropicStreamEventContentBlockStop)
    case messageDelta(AnthropicStreamEventMessageDelta)
    case messageStop(AnthropicStreamEventMessageStop)
    case ping(AnthropicStreamEventPing)
    case error(AnthropicStreamEventError)
    case unrecognized(String)

    private enum DiscriminatorKeys: String, CodingKey { case discriminator = "type" }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DiscriminatorKeys.self)
        let discriminator = try container.decode(String.self, forKey: .discriminator)
        switch discriminator {
        case "message_start": self = .messageStart(try AnthropicStreamEventMessageStart(from: decoder))
        case "content_block_start": self = .contentBlockStart(try AnthropicStreamEventContentBlockStart(from: decoder))
        case "content_block_delta": self = .contentBlockDelta(try AnthropicStreamEventContentBlockDelta(from: decoder))
        case "content_block_stop": self = .contentBlockStop(try AnthropicStreamEventContentBlockStop(from: decoder))
        case "message_delta": self = .messageDelta(try AnthropicStreamEventMessageDelta(from: decoder))
        case "message_stop": self = .messageStop(try AnthropicStreamEventMessageStop(from: decoder))
        case "ping": self = .ping(try AnthropicStreamEventPing(from: decoder))
        case "error": self = .error(try AnthropicStreamEventError(from: decoder))
        default: self = .unrecognized(discriminator)
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .messageStart(let value): try value.encode(to: encoder)
        case .contentBlockStart(let value): try value.encode(to: encoder)
        case .contentBlockDelta(let value): try value.encode(to: encoder)
        case .contentBlockStop(let value): try value.encode(to: encoder)
        case .messageDelta(let value): try value.encode(to: encoder)
        case .messageStop(let value): try value.encode(to: encoder)
        case .ping(let value): try value.encode(to: encoder)
        case .error(let value): try value.encode(to: encoder)
        case .unrecognized(let discriminator):
            var container = encoder.container(keyedBy: DiscriminatorKeys.self)
            try container.encode(discriminator, forKey: .discriminator)
        }
    }
}

public struct AnthropicStreamEventMessageStart: Codable, Sendable {
    public var type: String
    public var message: AnthropicStreamEventMessageStartMessage

    public init(type: String, message: AnthropicStreamEventMessageStartMessage) {
        self.type = type
        self.message = message
    }
}

public struct AnthropicStreamEventContentBlockStart: Codable, Sendable {
    public var type: String
    public var index: Double
    public var contentBlock: AnthropicResponseContentBlock

    enum CodingKeys: String, CodingKey {
        case type
        case index
        case contentBlock = "content_block"
    }

    public init(type: String, index: Double, contentBlock: AnthropicResponseContentBlock) {
        self.type = type
        self.index = index
        self.contentBlock = contentBlock
    }
}

public struct AnthropicStreamEventContentBlockDelta: Codable, Sendable {
    public var type: String
    public var index: Double
    public var delta: AnthropicBlockDelta

    public init(type: String, index: Double, delta: AnthropicBlockDelta) {
        self.type = type
        self.index = index
        self.delta = delta
    }
}

public struct AnthropicStreamEventContentBlockStop: Codable, Sendable {
    public var type: String
    public var index: Double

    public init(type: String, index: Double) {
        self.type = type
        self.index = index
    }
}

public struct AnthropicStreamEventMessageDelta: Codable, Sendable {
    public var type: String
    public var delta: AnthropicStreamEventMessageDeltaDelta
    public var usage: AnthropicStreamEventMessageDeltaUsage

    public init(type: String, delta: AnthropicStreamEventMessageDeltaDelta, usage: AnthropicStreamEventMessageDeltaUsage) {
        self.type = type
        self.delta = delta
        self.usage = usage
    }
}

public struct AnthropicStreamEventMessageStop: Codable, Sendable {
    public var type: String

    public init(type: String) {
        self.type = type
    }
}

public struct AnthropicStreamEventPing: Codable, Sendable {
    public var type: String

    public init(type: String) {
        self.type = type
    }
}

public struct AnthropicStreamEventError: Codable, Sendable {
    public var type: String
    public var error: AnthropicStreamEventErrorError

    public init(type: String, error: AnthropicStreamEventErrorError) {
        self.type = type
        self.error = error
    }
}

public struct AnthropicStreamEventMessageStartMessage: Codable, Sendable {
    public var id: String
    public var role: String
    public var model: String
    public var usage: AnthropicUsage

    public init(id: String, role: String, model: String, usage: AnthropicUsage) {
        self.id = id
        self.role = role
        self.model = model
        self.usage = usage
    }
}

public struct AnthropicStreamEventMessageDeltaDelta: Codable, Sendable {
    public var stopReason: String?
    public var stopSequence: String?

    enum CodingKeys: String, CodingKey {
        case stopReason = "stop_reason"
        case stopSequence = "stop_sequence"
    }

    public init(stopReason: String? = nil, stopSequence: String? = nil) {
        self.stopReason = stopReason
        self.stopSequence = stopSequence
    }
}

public struct AnthropicStreamEventMessageDeltaUsage: Codable, Sendable {
    public var outputTokens: Double

    enum CodingKeys: String, CodingKey {
        case outputTokens = "output_tokens"
    }

    public init(outputTokens: Double) {
        self.outputTokens = outputTokens
    }
}

public struct AnthropicStreamEventErrorError: Codable, Sendable {
    public var type: String
    public var message: String

    public init(type: String, message: String) {
        self.type = type
        self.message = message
    }
}

public struct GoogleInlineData: Codable, Sendable {
    public var mimeType: String
    public var data: String

    public init(mimeType: String, data: String) {
        self.mimeType = mimeType
        self.data = data
    }
}

public struct GoogleFileData: Codable, Sendable {
    public var mimeType: String?
    public var fileUri: String

    public init(mimeType: String? = nil, fileUri: String) {
        self.mimeType = mimeType
        self.fileUri = fileUri
    }
}

public enum GooglePart: Codable, Sendable {
    case text(String)
    case inlineData(GoogleInlineData)
    case fileData(GoogleFileData)
    case functionCall(GooglePartFunctionCall)
    case functionResponse(GooglePartFunctionResponse)
    case unrecognized(String)

    private enum CodingKeys: String, CodingKey {
        case text = "text"
        case inlineData = "inlineData"
        case fileData = "fileData"
        case functionCall = "functionCall"
        case functionResponse = "functionResponse"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let value = try container.decodeIfPresent(String.self, forKey: .text) {
            self = .text(value); return
        }
        if let value = try container.decodeIfPresent(GoogleInlineData.self, forKey: .inlineData) {
            self = .inlineData(value); return
        }
        if let value = try container.decodeIfPresent(GoogleFileData.self, forKey: .fileData) {
            self = .fileData(value); return
        }
        if let value = try container.decodeIfPresent(GooglePartFunctionCall.self, forKey: .functionCall) {
            self = .functionCall(value); return
        }
        if let value = try container.decodeIfPresent(GooglePartFunctionResponse.self, forKey: .functionResponse) {
            self = .functionResponse(value); return
        }
        let raw = try decoder.singleValueContainer().decode([String: SwitchboardJSON].self)
        self = .unrecognized(raw.keys.sorted().first ?? "")
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let value): try container.encode(value, forKey: .text)
        case .inlineData(let value): try container.encode(value, forKey: .inlineData)
        case .fileData(let value): try container.encode(value, forKey: .fileData)
        case .functionCall(let value): try container.encode(value, forKey: .functionCall)
        case .functionResponse(let value): try container.encode(value, forKey: .functionResponse)
        case .unrecognized:
            throw EncodingError.invalidValue(self, EncodingError.Context(codingPath: encoder.codingPath, debugDescription: "Cannot encode an unrecognized GooglePart tag"))
        }
    }
}

public struct GooglePartFunctionCall: Codable, Sendable {
    public var name: String
    public var args: SwitchboardJSON

    public init(name: String, args: SwitchboardJSON) {
        self.name = name
        self.args = args
    }
}

public struct GooglePartFunctionResponse: Codable, Sendable {
    public var name: String
    public var response: SwitchboardJSON

    public init(name: String, response: SwitchboardJSON) {
        self.name = name
        self.response = response
    }
}

public struct GoogleContent: Codable, Sendable {
    public var role: GoogleContentRole
    public var parts: [GooglePart]

    public init(role: GoogleContentRole, parts: [GooglePart]) {
        self.role = role
        self.parts = parts
    }
}

public enum GoogleContentRole: String, Codable, Sendable {
    case user
    case model
}

public struct GoogleSystemInstruction: Codable, Sendable {
    public var parts: [GooglePart]

    public init(parts: [GooglePart]) {
        self.parts = parts
    }
}

public struct GoogleFunctionDeclaration: Codable, Sendable {
    public var name: String
    public var description: String?
    public var parameters: SwitchboardJSON?

    public init(name: String, description: String? = nil, parameters: SwitchboardJSON? = nil) {
        self.name = name
        self.description = description
        self.parameters = parameters
    }
}

public struct GoogleTool: Codable, Sendable {
    public var functionDeclarations: [GoogleFunctionDeclaration]?

    public init(functionDeclarations: [GoogleFunctionDeclaration]? = nil) {
        self.functionDeclarations = functionDeclarations
    }
}

public enum GoogleFunctionCallingMode: String, Codable, Sendable {
    case AUTO
    case ANY
    case NONE
}

public struct GoogleFunctionCallingConfig: Codable, Sendable {
    public var mode: GoogleFunctionCallingMode?
    public var allowedFunctionNames: [String]?

    public init(mode: GoogleFunctionCallingMode? = nil, allowedFunctionNames: [String]? = nil) {
        self.mode = mode
        self.allowedFunctionNames = allowedFunctionNames
    }
}

public struct GoogleToolConfig: Codable, Sendable {
    public var functionCallingConfig: GoogleFunctionCallingConfig?

    public init(functionCallingConfig: GoogleFunctionCallingConfig? = nil) {
        self.functionCallingConfig = functionCallingConfig
    }
}

public struct GoogleThinkingConfig: Codable, Sendable {
    public var thinkingBudget: Double?
    public var includeThoughts: Bool?

    public init(thinkingBudget: Double? = nil, includeThoughts: Bool? = nil) {
        self.thinkingBudget = thinkingBudget
        self.includeThoughts = includeThoughts
    }
}

public struct GoogleGenerationConfig: Codable, Sendable {
    public var temperature: Double?
    public var topP: Double?
    public var topK: Double?
    public var maxOutputTokens: Double?
    public var stopSequences: [String]?
    public var candidateCount: Double?
    public var responseMimeType: String?
    public var responseSchema: SwitchboardJSON?
    public var thinkingConfig: GoogleThinkingConfig?

    public init(temperature: Double? = nil, topP: Double? = nil, topK: Double? = nil, maxOutputTokens: Double? = nil, stopSequences: [String]? = nil, candidateCount: Double? = nil, responseMimeType: String? = nil, responseSchema: SwitchboardJSON? = nil, thinkingConfig: GoogleThinkingConfig? = nil) {
        self.temperature = temperature
        self.topP = topP
        self.topK = topK
        self.maxOutputTokens = maxOutputTokens
        self.stopSequences = stopSequences
        self.candidateCount = candidateCount
        self.responseMimeType = responseMimeType
        self.responseSchema = responseSchema
        self.thinkingConfig = thinkingConfig
    }
}

public struct GoogleSafetySetting: Codable, Sendable {
    public var category: String
    public var threshold: String

    public init(category: String, threshold: String) {
        self.category = category
        self.threshold = threshold
    }
}

public struct GoogleGenerateContentRequest: Codable, Sendable {
    public var model: String
    public var contents: [GoogleContent]
    public var systemInstruction: GoogleSystemInstruction?
    public var tools: [GoogleTool]?
    public var toolConfig: GoogleToolConfig?
    public var generationConfig: GoogleGenerationConfig?
    public var safetySettings: [GoogleSafetySetting]?
    public var stream: Bool?

    public init(model: String, contents: [GoogleContent], systemInstruction: GoogleSystemInstruction? = nil, tools: [GoogleTool]? = nil, toolConfig: GoogleToolConfig? = nil, generationConfig: GoogleGenerationConfig? = nil, safetySettings: [GoogleSafetySetting]? = nil, stream: Bool? = nil) {
        self.model = model
        self.contents = contents
        self.systemInstruction = systemInstruction
        self.tools = tools
        self.toolConfig = toolConfig
        self.generationConfig = generationConfig
        self.safetySettings = safetySettings
        self.stream = stream
    }
}

public struct GoogleUsageMetadata: Codable, Sendable {
    public var promptTokenCount: Double?
    public var candidatesTokenCount: Double?
    public var thoughtsTokenCount: Double?
    public var cachedContentTokenCount: Double?
    public var totalTokenCount: Double?

    public init(promptTokenCount: Double? = nil, candidatesTokenCount: Double? = nil, thoughtsTokenCount: Double? = nil, cachedContentTokenCount: Double? = nil, totalTokenCount: Double? = nil) {
        self.promptTokenCount = promptTokenCount
        self.candidatesTokenCount = candidatesTokenCount
        self.thoughtsTokenCount = thoughtsTokenCount
        self.cachedContentTokenCount = cachedContentTokenCount
        self.totalTokenCount = totalTokenCount
    }
}

public enum GoogleFinishReason: String, Codable, Sendable {
    case STOP
    case MAXTOKENS = "MAX_TOKENS"
    case SAFETY
    case RECITATION
    case BLOCKLIST
    case PROHIBITEDCONTENT = "PROHIBITED_CONTENT"
    case SPII
    case MALFORMEDFUNCTIONCALL = "MALFORMED_FUNCTION_CALL"
    case OTHER
}

public struct GoogleCandidate: Codable, Sendable {
    public var content: GoogleContent?
    public var finishReason: GoogleFinishReason?
    public var index: Double?

    public init(content: GoogleContent? = nil, finishReason: GoogleFinishReason? = nil, index: Double? = nil) {
        self.content = content
        self.finishReason = finishReason
        self.index = index
    }
}

public struct GoogleGenerateContentResponse: Codable, Sendable {
    public var candidates: [GoogleCandidate]?
    public var usageMetadata: GoogleUsageMetadata?
    public var modelVersion: String?
    public var responseId: String?

    public init(candidates: [GoogleCandidate]? = nil, usageMetadata: GoogleUsageMetadata? = nil, modelVersion: String? = nil, responseId: String? = nil) {
        self.candidates = candidates
        self.usageMetadata = usageMetadata
        self.modelVersion = modelVersion
        self.responseId = responseId
    }
}

public enum OpenAIContentPart: Codable, Sendable {
    case text(OpenAIContentPartText)
    case imageUrl(OpenAIContentPartImageUrl)
    case unrecognized(String)

    private enum DiscriminatorKeys: String, CodingKey { case discriminator = "type" }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DiscriminatorKeys.self)
        let discriminator = try container.decode(String.self, forKey: .discriminator)
        switch discriminator {
        case "text": self = .text(try OpenAIContentPartText(from: decoder))
        case "image_url": self = .imageUrl(try OpenAIContentPartImageUrl(from: decoder))
        default: self = .unrecognized(discriminator)
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .text(let value): try value.encode(to: encoder)
        case .imageUrl(let value): try value.encode(to: encoder)
        case .unrecognized(let discriminator):
            var container = encoder.container(keyedBy: DiscriminatorKeys.self)
            try container.encode(discriminator, forKey: .discriminator)
        }
    }
}

public struct OpenAIContentPartText: Codable, Sendable {
    public var type: String
    public var text: String

    public init(type: String, text: String) {
        self.type = type
        self.text = text
    }
}

public struct OpenAIContentPartImageUrl: Codable, Sendable {
    public var type: String
    public var imageUrl: OpenAIContentPartImageUrlImageUrl

    enum CodingKeys: String, CodingKey {
        case type
        case imageUrl = "image_url"
    }

    public init(type: String, imageUrl: OpenAIContentPartImageUrlImageUrl) {
        self.type = type
        self.imageUrl = imageUrl
    }
}

public struct OpenAIContentPartImageUrlImageUrl: Codable, Sendable {
    public var url: String
    public var detail: OpenAIContentPartImageUrlImageUrlDetail?

    public init(url: String, detail: OpenAIContentPartImageUrlImageUrlDetail? = nil) {
        self.url = url
        self.detail = detail
    }
}

public enum OpenAIContentPartImageUrlImageUrlDetail: String, Codable, Sendable {
    case auto
    case low
    case high
}

public struct OpenAIToolCall: Codable, Sendable {
    public var id: String
    public var type: String
    public var function: OpenAIToolCallFunction

    public init(id: String, type: String, function: OpenAIToolCallFunction) {
        self.id = id
        self.type = type
        self.function = function
    }
}

public struct OpenAIToolCallFunction: Codable, Sendable {
    public var name: String
    public var arguments: String

    public init(name: String, arguments: String) {
        self.name = name
        self.arguments = arguments
    }
}

public struct OpenAIChatMessage: Codable, Sendable {
    public var role: OpenAIChatMessageRole
    public var content: SwitchboardJSON?
    public var name: String?
    public var toolCalls: [OpenAIToolCall]?
    public var toolCallId: String?

    enum CodingKeys: String, CodingKey {
        case role
        case content
        case name
        case toolCalls = "tool_calls"
        case toolCallId = "tool_call_id"
    }

    public init(role: OpenAIChatMessageRole, content: SwitchboardJSON? = nil, name: String? = nil, toolCalls: [OpenAIToolCall]? = nil, toolCallId: String? = nil) {
        self.role = role
        self.content = content
        self.name = name
        self.toolCalls = toolCalls
        self.toolCallId = toolCallId
    }
}

public enum OpenAIChatMessageRole: String, Codable, Sendable {
    case system
    case developer
    case user
    case assistant
    case tool
}

public struct OpenAITool: Codable, Sendable {
    public var type: String
    public var function: OpenAIToolFunction

    public init(type: String, function: OpenAIToolFunction) {
        self.type = type
        self.function = function
    }
}

public struct OpenAIToolFunction: Codable, Sendable {
    public var name: String
    public var description: String?
    public var parameters: SwitchboardJSON?
    public var strict: Bool?

    public init(name: String, description: String? = nil, parameters: SwitchboardJSON? = nil, strict: Bool? = nil) {
        self.name = name
        self.description = description
        self.parameters = parameters
        self.strict = strict
    }
}

public enum OpenAIToolChoice: Codable, Sendable {
    case auto
    case `none`
    case required
    case function(OpenAIToolChoiceFunction)
    case unrecognized(String)
    case unrecognizedObject(String)

    private enum DiscriminatorKeys: String, CodingKey { case discriminator = "type" }

    public init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer(), let raw = try? single.decode(String.self) {
            switch raw {
            case "auto": self = .auto; return
            case "none": self = .`none`; return
            case "required": self = .required; return
            default: self = .unrecognized(raw); return
            }
        }
        let container = try decoder.container(keyedBy: DiscriminatorKeys.self)
        let discriminator = try container.decode(String.self, forKey: .discriminator)
        switch discriminator {
        case "function": self = .function(try OpenAIToolChoiceFunction(from: decoder))
        default: self = .unrecognizedObject(discriminator)
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .auto:
            var container = encoder.singleValueContainer()
            try container.encode("auto")
        case .`none`:
            var container = encoder.singleValueContainer()
            try container.encode("none")
        case .required:
            var container = encoder.singleValueContainer()
            try container.encode("required")
        case .function(let value): try value.encode(to: encoder)
        case .unrecognized(let discriminator):
            var container = encoder.singleValueContainer()
            try container.encode(discriminator)
        case .unrecognizedObject(let discriminator):
            var container = encoder.container(keyedBy: DiscriminatorKeys.self)
            try container.encode(discriminator, forKey: .discriminator)
        }
    }
}

public struct OpenAIToolChoiceFunction: Codable, Sendable {
    public var type: String
    public var function: OpenAIToolChoiceFunctionFunction

    public init(type: String, function: OpenAIToolChoiceFunctionFunction) {
        self.type = type
        self.function = function
    }
}

public struct OpenAIToolChoiceFunctionFunction: Codable, Sendable {
    public var name: String

    public init(name: String) {
        self.name = name
    }
}

public struct OpenAIChatRequest: Codable, Sendable {
    public var model: String
    public var messages: [OpenAIChatMessage]
    public var maxCompletionTokens: Double?
    public var maxTokens: Double?
    public var temperature: Double?
    public var topP: Double?
    public var frequencyPenalty: Double?
    public var presencePenalty: Double?
    public var seed: Double?
    public var n: Double?
    public var logitBias: SwitchboardJSON?
    public var stop: SwitchboardJSON?
    public var stream: Bool?
    public var streamOptions: OpenAIChatRequestStreamOptions?
    public var tools: [OpenAITool]?
    public var toolChoice: OpenAIToolChoice?
    public var parallelToolCalls: Bool?
    public var responseFormat: SwitchboardJSON?
    public var reasoningEffort: OpenAIChatRequestReasoningEffort?
    public var verbosity: OpenAIChatRequestVerbosity?
    public var promptCacheKey: String?
    public var store: Bool?
    public var metadata: SwitchboardJSON?
    public var user: String?

    enum CodingKeys: String, CodingKey {
        case model
        case messages
        case maxCompletionTokens = "max_completion_tokens"
        case maxTokens = "max_tokens"
        case temperature
        case topP = "top_p"
        case frequencyPenalty = "frequency_penalty"
        case presencePenalty = "presence_penalty"
        case seed
        case n
        case logitBias = "logit_bias"
        case stop
        case stream
        case streamOptions = "stream_options"
        case tools
        case toolChoice = "tool_choice"
        case parallelToolCalls = "parallel_tool_calls"
        case responseFormat = "response_format"
        case reasoningEffort = "reasoning_effort"
        case verbosity
        case promptCacheKey = "prompt_cache_key"
        case store
        case metadata
        case user
    }

    public init(model: String, messages: [OpenAIChatMessage], maxCompletionTokens: Double? = nil, maxTokens: Double? = nil, temperature: Double? = nil, topP: Double? = nil, frequencyPenalty: Double? = nil, presencePenalty: Double? = nil, seed: Double? = nil, n: Double? = nil, logitBias: SwitchboardJSON? = nil, stop: SwitchboardJSON? = nil, stream: Bool? = nil, streamOptions: OpenAIChatRequestStreamOptions? = nil, tools: [OpenAITool]? = nil, toolChoice: OpenAIToolChoice? = nil, parallelToolCalls: Bool? = nil, responseFormat: SwitchboardJSON? = nil, reasoningEffort: OpenAIChatRequestReasoningEffort? = nil, verbosity: OpenAIChatRequestVerbosity? = nil, promptCacheKey: String? = nil, store: Bool? = nil, metadata: SwitchboardJSON? = nil, user: String? = nil) {
        self.model = model
        self.messages = messages
        self.maxCompletionTokens = maxCompletionTokens
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.topP = topP
        self.frequencyPenalty = frequencyPenalty
        self.presencePenalty = presencePenalty
        self.seed = seed
        self.n = n
        self.logitBias = logitBias
        self.stop = stop
        self.stream = stream
        self.streamOptions = streamOptions
        self.tools = tools
        self.toolChoice = toolChoice
        self.parallelToolCalls = parallelToolCalls
        self.responseFormat = responseFormat
        self.reasoningEffort = reasoningEffort
        self.verbosity = verbosity
        self.promptCacheKey = promptCacheKey
        self.store = store
        self.metadata = metadata
        self.user = user
    }
}

public struct OpenAIChatRequestStreamOptions: Codable, Sendable {
    public var includeUsage: Bool?

    enum CodingKeys: String, CodingKey {
        case includeUsage = "include_usage"
    }

    public init(includeUsage: Bool? = nil) {
        self.includeUsage = includeUsage
    }
}

public enum OpenAIChatRequestReasoningEffort: String, Codable, Sendable {
    case `none` = "none"
    case minimal
    case low
    case medium
    case high
    case xhigh
    case max
}

public enum OpenAIChatRequestVerbosity: String, Codable, Sendable {
    case low
    case medium
    case high
}

public struct OpenAIUsage: Codable, Sendable {
    public var promptTokens: Double
    public var completionTokens: Double
    public var totalTokens: Double
    public var promptTokensDetails: OpenAIUsagePromptTokensDetails?
    public var completionTokensDetails: OpenAIUsageCompletionTokensDetails?

    enum CodingKeys: String, CodingKey {
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case totalTokens = "total_tokens"
        case promptTokensDetails = "prompt_tokens_details"
        case completionTokensDetails = "completion_tokens_details"
    }

    public init(promptTokens: Double, completionTokens: Double, totalTokens: Double, promptTokensDetails: OpenAIUsagePromptTokensDetails? = nil, completionTokensDetails: OpenAIUsageCompletionTokensDetails? = nil) {
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.totalTokens = totalTokens
        self.promptTokensDetails = promptTokensDetails
        self.completionTokensDetails = completionTokensDetails
    }
}

public struct OpenAIUsagePromptTokensDetails: Codable, Sendable {
    public var cachedTokens: Double?
    public var cacheWriteTokens: Double?
    public var audioTokens: Double?

    enum CodingKeys: String, CodingKey {
        case cachedTokens = "cached_tokens"
        case cacheWriteTokens = "cache_write_tokens"
        case audioTokens = "audio_tokens"
    }

    public init(cachedTokens: Double? = nil, cacheWriteTokens: Double? = nil, audioTokens: Double? = nil) {
        self.cachedTokens = cachedTokens
        self.cacheWriteTokens = cacheWriteTokens
        self.audioTokens = audioTokens
    }
}

public struct OpenAIUsageCompletionTokensDetails: Codable, Sendable {
    public var reasoningTokens: Double?
    public var acceptedPredictionTokens: Double?
    public var rejectedPredictionTokens: Double?
    public var audioTokens: Double?

    enum CodingKeys: String, CodingKey {
        case reasoningTokens = "reasoning_tokens"
        case acceptedPredictionTokens = "accepted_prediction_tokens"
        case rejectedPredictionTokens = "rejected_prediction_tokens"
        case audioTokens = "audio_tokens"
    }

    public init(reasoningTokens: Double? = nil, acceptedPredictionTokens: Double? = nil, rejectedPredictionTokens: Double? = nil, audioTokens: Double? = nil) {
        self.reasoningTokens = reasoningTokens
        self.acceptedPredictionTokens = acceptedPredictionTokens
        self.rejectedPredictionTokens = rejectedPredictionTokens
        self.audioTokens = audioTokens
    }
}

public struct OpenAIChatResponseMessage: Codable, Sendable {
    public var role: String
    public var content: String?
    public var toolCalls: [OpenAIToolCall]?

    enum CodingKeys: String, CodingKey {
        case role
        case content
        case toolCalls = "tool_calls"
    }

    public init(role: String, content: String? = nil, toolCalls: [OpenAIToolCall]? = nil) {
        self.role = role
        self.content = content
        self.toolCalls = toolCalls
    }
}

public enum OpenAIFinishReason: String, Codable, Sendable {
    case stop
    case length
    case toolCalls = "tool_calls"
    case contentFilter = "content_filter"
}

public struct OpenAIChatResponse: Codable, Sendable {
    public var id: String
    public var object: String
    public var model: String
    public var choices: [OpenAIChatResponseChoices]
    public var usage: OpenAIUsage

    public init(id: String, object: String, model: String, choices: [OpenAIChatResponseChoices], usage: OpenAIUsage) {
        self.id = id
        self.object = object
        self.model = model
        self.choices = choices
        self.usage = usage
    }
}

public struct OpenAIChatResponseChoices: Codable, Sendable {
    public var index: Double
    public var message: OpenAIChatResponseMessage
    public var finishReason: OpenAIFinishReason?

    enum CodingKeys: String, CodingKey {
        case index
        case message
        case finishReason = "finish_reason"
    }

    public init(index: Double, message: OpenAIChatResponseMessage, finishReason: OpenAIFinishReason? = nil) {
        self.index = index
        self.message = message
        self.finishReason = finishReason
    }
}

public struct OpenAIChatDelta: Codable, Sendable {
    public var role: String?
    public var content: String?
    public var toolCalls: [OpenAIChatDeltaToolCalls]?

    enum CodingKeys: String, CodingKey {
        case role
        case content
        case toolCalls = "tool_calls"
    }

    public init(role: String? = nil, content: String? = nil, toolCalls: [OpenAIChatDeltaToolCalls]? = nil) {
        self.role = role
        self.content = content
        self.toolCalls = toolCalls
    }
}

public struct OpenAIChatDeltaToolCalls: Codable, Sendable {
    public var index: Double
    public var id: String?
    public var type: String?
    public var function: OpenAIChatDeltaToolCallsFunction?

    public init(index: Double, id: String? = nil, type: String? = nil, function: OpenAIChatDeltaToolCallsFunction? = nil) {
        self.index = index
        self.id = id
        self.type = type
        self.function = function
    }
}

public struct OpenAIChatDeltaToolCallsFunction: Codable, Sendable {
    public var name: String?
    public var arguments: String?

    public init(name: String? = nil, arguments: String? = nil) {
        self.name = name
        self.arguments = arguments
    }
}

public struct OpenAIChatChunk: Codable, Sendable {
    public var id: String
    public var object: String
    public var model: String
    public var choices: [OpenAIChatChunkChoices]
    public var usage: OpenAIUsage?

    public init(id: String, object: String, model: String, choices: [OpenAIChatChunkChoices], usage: OpenAIUsage? = nil) {
        self.id = id
        self.object = object
        self.model = model
        self.choices = choices
        self.usage = usage
    }
}

public struct OpenAIChatChunkChoices: Codable, Sendable {
    public var index: Double
    public var delta: OpenAIChatDelta
    public var finishReason: OpenAIFinishReason?

    enum CodingKeys: String, CodingKey {
        case index
        case delta
        case finishReason = "finish_reason"
    }

    public init(index: Double, delta: OpenAIChatDelta, finishReason: OpenAIFinishReason? = nil) {
        self.index = index
        self.delta = delta
        self.finishReason = finishReason
    }
}

public enum OpenAIResponsesContentPart: Codable, Sendable {
    case inputText(OpenAIResponsesContentPartInputText)
    case inputImage(OpenAIResponsesContentPartInputImage)
    case outputText(OpenAIResponsesContentPartOutputText)
    case unrecognized(String)

    private enum DiscriminatorKeys: String, CodingKey { case discriminator = "type" }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DiscriminatorKeys.self)
        let discriminator = try container.decode(String.self, forKey: .discriminator)
        switch discriminator {
        case "input_text": self = .inputText(try OpenAIResponsesContentPartInputText(from: decoder))
        case "input_image": self = .inputImage(try OpenAIResponsesContentPartInputImage(from: decoder))
        case "output_text": self = .outputText(try OpenAIResponsesContentPartOutputText(from: decoder))
        default: self = .unrecognized(discriminator)
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .inputText(let value): try value.encode(to: encoder)
        case .inputImage(let value): try value.encode(to: encoder)
        case .outputText(let value): try value.encode(to: encoder)
        case .unrecognized(let discriminator):
            var container = encoder.container(keyedBy: DiscriminatorKeys.self)
            try container.encode(discriminator, forKey: .discriminator)
        }
    }
}

public struct OpenAIResponsesContentPartInputText: Codable, Sendable {
    public var type: String
    public var text: String

    public init(type: String, text: String) {
        self.type = type
        self.text = text
    }
}

public struct OpenAIResponsesContentPartInputImage: Codable, Sendable {
    public var type: String
    public var imageUrl: String
    public var detail: OpenAIResponsesContentPartInputImageDetail?

    enum CodingKeys: String, CodingKey {
        case type
        case imageUrl = "image_url"
        case detail
    }

    public init(type: String, imageUrl: String, detail: OpenAIResponsesContentPartInputImageDetail? = nil) {
        self.type = type
        self.imageUrl = imageUrl
        self.detail = detail
    }
}

public struct OpenAIResponsesContentPartOutputText: Codable, Sendable {
    public var type: String
    public var text: String

    public init(type: String, text: String) {
        self.type = type
        self.text = text
    }
}

public enum OpenAIResponsesContentPartInputImageDetail: String, Codable, Sendable {
    case auto
    case low
    case high
}

public enum OpenAIResponsesInputItem: Codable, Sendable {
    case message(OpenAIResponsesInputItemMessage)
    case functionCall(OpenAIResponsesInputItemFunctionCall)
    case functionCallOutput(OpenAIResponsesInputItemFunctionCallOutput)
    case reasoning(OpenAIResponsesInputItemReasoning)
    case unrecognized(String)

    private enum DiscriminatorKeys: String, CodingKey { case discriminator = "type" }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DiscriminatorKeys.self)
        let discriminator = try container.decode(String.self, forKey: .discriminator)
        switch discriminator {
        case "message": self = .message(try OpenAIResponsesInputItemMessage(from: decoder))
        case "function_call": self = .functionCall(try OpenAIResponsesInputItemFunctionCall(from: decoder))
        case "function_call_output": self = .functionCallOutput(try OpenAIResponsesInputItemFunctionCallOutput(from: decoder))
        case "reasoning": self = .reasoning(try OpenAIResponsesInputItemReasoning(from: decoder))
        default: self = .unrecognized(discriminator)
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .message(let value): try value.encode(to: encoder)
        case .functionCall(let value): try value.encode(to: encoder)
        case .functionCallOutput(let value): try value.encode(to: encoder)
        case .reasoning(let value): try value.encode(to: encoder)
        case .unrecognized(let discriminator):
            var container = encoder.container(keyedBy: DiscriminatorKeys.self)
            try container.encode(discriminator, forKey: .discriminator)
        }
    }
}

public struct OpenAIResponsesInputItemMessage: Codable, Sendable {
    public var type: String
    public var role: OpenAIResponsesInputItemMessageRole
    public var content: SwitchboardJSON

    public init(type: String, role: OpenAIResponsesInputItemMessageRole, content: SwitchboardJSON) {
        self.type = type
        self.role = role
        self.content = content
    }
}

public struct OpenAIResponsesInputItemFunctionCall: Codable, Sendable {
    public var type: String
    public var callId: String
    public var name: String
    public var arguments: String

    enum CodingKeys: String, CodingKey {
        case type
        case callId = "call_id"
        case name
        case arguments
    }

    public init(type: String, callId: String, name: String, arguments: String) {
        self.type = type
        self.callId = callId
        self.name = name
        self.arguments = arguments
    }
}

public struct OpenAIResponsesInputItemFunctionCallOutput: Codable, Sendable {
    public var type: String
    public var callId: String
    public var output: String

    enum CodingKeys: String, CodingKey {
        case type
        case callId = "call_id"
        case output
    }

    public init(type: String, callId: String, output: String) {
        self.type = type
        self.callId = callId
        self.output = output
    }
}

public struct OpenAIResponsesInputItemReasoning: Codable, Sendable {
    public var type: String
    public var id: String
    public var summary: [SwitchboardJSON]

    public init(type: String, id: String, summary: [SwitchboardJSON]) {
        self.type = type
        self.id = id
        self.summary = summary
    }
}

public enum OpenAIResponsesInputItemMessageRole: String, Codable, Sendable {
    case system
    case developer
    case user
    case assistant
}

public struct OpenAIResponsesTool: Codable, Sendable {
    public var type: String
    public var name: String
    public var description: String?
    public var parameters: SwitchboardJSON?
    public var strict: Bool?

    public init(type: String, name: String, description: String? = nil, parameters: SwitchboardJSON? = nil, strict: Bool? = nil) {
        self.type = type
        self.name = name
        self.description = description
        self.parameters = parameters
        self.strict = strict
    }
}

public enum OpenAIResponsesToolChoice: Codable, Sendable {
    case auto
    case `none`
    case required
    case function(OpenAIResponsesToolChoiceFunction)
    case unrecognized(String)
    case unrecognizedObject(String)

    private enum DiscriminatorKeys: String, CodingKey { case discriminator = "type" }

    public init(from decoder: Decoder) throws {
        if let single = try? decoder.singleValueContainer(), let raw = try? single.decode(String.self) {
            switch raw {
            case "auto": self = .auto; return
            case "none": self = .`none`; return
            case "required": self = .required; return
            default: self = .unrecognized(raw); return
            }
        }
        let container = try decoder.container(keyedBy: DiscriminatorKeys.self)
        let discriminator = try container.decode(String.self, forKey: .discriminator)
        switch discriminator {
        case "function": self = .function(try OpenAIResponsesToolChoiceFunction(from: decoder))
        default: self = .unrecognizedObject(discriminator)
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .auto:
            var container = encoder.singleValueContainer()
            try container.encode("auto")
        case .`none`:
            var container = encoder.singleValueContainer()
            try container.encode("none")
        case .required:
            var container = encoder.singleValueContainer()
            try container.encode("required")
        case .function(let value): try value.encode(to: encoder)
        case .unrecognized(let discriminator):
            var container = encoder.singleValueContainer()
            try container.encode(discriminator)
        case .unrecognizedObject(let discriminator):
            var container = encoder.container(keyedBy: DiscriminatorKeys.self)
            try container.encode(discriminator, forKey: .discriminator)
        }
    }
}

public struct OpenAIResponsesToolChoiceFunction: Codable, Sendable {
    public var type: String
    public var name: String

    public init(type: String, name: String) {
        self.type = type
        self.name = name
    }
}

public struct OpenAIResponsesRequest: Codable, Sendable {
    public var model: String
    public var input: SwitchboardJSON
    public var instructions: String?
    public var maxOutputTokens: Double?
    public var maxToolCalls: Double?
    public var temperature: Double?
    public var topP: Double?
    public var stream: Bool?
    public var tools: [OpenAIResponsesTool]?
    public var toolChoice: OpenAIResponsesToolChoice?
    public var parallelToolCalls: Bool?
    public var reasoning: OpenAIResponsesRequestReasoning?
    public var text: OpenAIResponsesRequestText?
    public var include: [String]?
    public var store: Bool?
    public var previousResponseId: String?
    public var promptCacheKey: String?
    public var metadata: SwitchboardJSON?

    enum CodingKeys: String, CodingKey {
        case model
        case input
        case instructions
        case maxOutputTokens = "max_output_tokens"
        case maxToolCalls = "max_tool_calls"
        case temperature
        case topP = "top_p"
        case stream
        case tools
        case toolChoice = "tool_choice"
        case parallelToolCalls = "parallel_tool_calls"
        case reasoning
        case text
        case include
        case store
        case previousResponseId = "previous_response_id"
        case promptCacheKey = "prompt_cache_key"
        case metadata
    }

    public init(model: String, input: SwitchboardJSON, instructions: String? = nil, maxOutputTokens: Double? = nil, maxToolCalls: Double? = nil, temperature: Double? = nil, topP: Double? = nil, stream: Bool? = nil, tools: [OpenAIResponsesTool]? = nil, toolChoice: OpenAIResponsesToolChoice? = nil, parallelToolCalls: Bool? = nil, reasoning: OpenAIResponsesRequestReasoning? = nil, text: OpenAIResponsesRequestText? = nil, include: [String]? = nil, store: Bool? = nil, previousResponseId: String? = nil, promptCacheKey: String? = nil, metadata: SwitchboardJSON? = nil) {
        self.model = model
        self.input = input
        self.instructions = instructions
        self.maxOutputTokens = maxOutputTokens
        self.maxToolCalls = maxToolCalls
        self.temperature = temperature
        self.topP = topP
        self.stream = stream
        self.tools = tools
        self.toolChoice = toolChoice
        self.parallelToolCalls = parallelToolCalls
        self.reasoning = reasoning
        self.text = text
        self.include = include
        self.store = store
        self.previousResponseId = previousResponseId
        self.promptCacheKey = promptCacheKey
        self.metadata = metadata
    }
}

public struct OpenAIResponsesRequestReasoning: Codable, Sendable {
    public var effort: OpenAIResponsesRequestReasoningEffort?
    public var summary: OpenAIResponsesRequestReasoningSummary?

    public init(effort: OpenAIResponsesRequestReasoningEffort? = nil, summary: OpenAIResponsesRequestReasoningSummary? = nil) {
        self.effort = effort
        self.summary = summary
    }
}

public struct OpenAIResponsesRequestText: Codable, Sendable {
    public var format: SwitchboardJSON?
    public var verbosity: OpenAIResponsesRequestTextVerbosity?

    public init(format: SwitchboardJSON? = nil, verbosity: OpenAIResponsesRequestTextVerbosity? = nil) {
        self.format = format
        self.verbosity = verbosity
    }
}

public enum OpenAIResponsesRequestReasoningEffort: String, Codable, Sendable {
    case `none` = "none"
    case minimal
    case low
    case medium
    case high
    case xhigh
    case max
}

public enum OpenAIResponsesRequestReasoningSummary: String, Codable, Sendable {
    case auto
    case concise
    case detailed
}

public enum OpenAIResponsesRequestTextVerbosity: String, Codable, Sendable {
    case low
    case medium
    case high
}

public struct OpenAIResponsesUsage: Codable, Sendable {
    public var inputTokens: Double
    public var outputTokens: Double
    public var totalTokens: Double
    public var inputTokensDetails: OpenAIResponsesUsageInputTokensDetails?
    public var outputTokensDetails: OpenAIResponsesUsageOutputTokensDetails?

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case outputTokens = "output_tokens"
        case totalTokens = "total_tokens"
        case inputTokensDetails = "input_tokens_details"
        case outputTokensDetails = "output_tokens_details"
    }

    public init(inputTokens: Double, outputTokens: Double, totalTokens: Double, inputTokensDetails: OpenAIResponsesUsageInputTokensDetails? = nil, outputTokensDetails: OpenAIResponsesUsageOutputTokensDetails? = nil) {
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.totalTokens = totalTokens
        self.inputTokensDetails = inputTokensDetails
        self.outputTokensDetails = outputTokensDetails
    }
}

public struct OpenAIResponsesUsageInputTokensDetails: Codable, Sendable {
    public var cachedTokens: Double?
    public var cacheWriteTokens: Double?

    enum CodingKeys: String, CodingKey {
        case cachedTokens = "cached_tokens"
        case cacheWriteTokens = "cache_write_tokens"
    }

    public init(cachedTokens: Double? = nil, cacheWriteTokens: Double? = nil) {
        self.cachedTokens = cachedTokens
        self.cacheWriteTokens = cacheWriteTokens
    }
}

public struct OpenAIResponsesUsageOutputTokensDetails: Codable, Sendable {
    public var reasoningTokens: Double?

    enum CodingKeys: String, CodingKey {
        case reasoningTokens = "reasoning_tokens"
    }

    public init(reasoningTokens: Double? = nil) {
        self.reasoningTokens = reasoningTokens
    }
}

public enum OpenAIResponsesOutputItem: Codable, Sendable {
    case message(OpenAIResponsesOutputItemMessage)
    case functionCall(OpenAIResponsesOutputItemFunctionCall)
    case reasoning(OpenAIResponsesOutputItemReasoning)
    case unrecognized(String)

    private enum DiscriminatorKeys: String, CodingKey { case discriminator = "type" }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DiscriminatorKeys.self)
        let discriminator = try container.decode(String.self, forKey: .discriminator)
        switch discriminator {
        case "message": self = .message(try OpenAIResponsesOutputItemMessage(from: decoder))
        case "function_call": self = .functionCall(try OpenAIResponsesOutputItemFunctionCall(from: decoder))
        case "reasoning": self = .reasoning(try OpenAIResponsesOutputItemReasoning(from: decoder))
        default: self = .unrecognized(discriminator)
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .message(let value): try value.encode(to: encoder)
        case .functionCall(let value): try value.encode(to: encoder)
        case .reasoning(let value): try value.encode(to: encoder)
        case .unrecognized(let discriminator):
            var container = encoder.container(keyedBy: DiscriminatorKeys.self)
            try container.encode(discriminator, forKey: .discriminator)
        }
    }
}

public struct OpenAIResponsesOutputItemMessage: Codable, Sendable {
    public var type: String
    public var id: String
    public var role: String
    public var content: [OpenAIResponsesOutputItemMessageContent]

    public init(type: String, id: String, role: String, content: [OpenAIResponsesOutputItemMessageContent]) {
        self.type = type
        self.id = id
        self.role = role
        self.content = content
    }
}

public struct OpenAIResponsesOutputItemFunctionCall: Codable, Sendable {
    public var type: String
    public var id: String
    public var callId: String
    public var name: String
    public var arguments: String

    enum CodingKeys: String, CodingKey {
        case type
        case id
        case callId = "call_id"
        case name
        case arguments
    }

    public init(type: String, id: String, callId: String, name: String, arguments: String) {
        self.type = type
        self.id = id
        self.callId = callId
        self.name = name
        self.arguments = arguments
    }
}

public struct OpenAIResponsesOutputItemReasoning: Codable, Sendable {
    public var type: String
    public var id: String
    public var summary: [SwitchboardJSON]

    public init(type: String, id: String, summary: [SwitchboardJSON]) {
        self.type = type
        self.id = id
        self.summary = summary
    }
}

public struct OpenAIResponsesOutputItemMessageContent: Codable, Sendable {
    public var type: String
    public var text: String

    public init(type: String, text: String) {
        self.type = type
        self.text = text
    }
}

public struct OpenAIResponsesResponse: Codable, Sendable {
    public var id: String
    public var object: String
    public var model: String
    public var status: OpenAIResponsesResponseStatus
    public var output: [OpenAIResponsesOutputItem]
    public var usage: OpenAIResponsesUsage

    public init(id: String, object: String, model: String, status: OpenAIResponsesResponseStatus, output: [OpenAIResponsesOutputItem], usage: OpenAIResponsesUsage) {
        self.id = id
        self.object = object
        self.model = model
        self.status = status
        self.output = output
        self.usage = usage
    }
}

public enum OpenAIResponsesResponseStatus: String, Codable, Sendable {
    case completed
    case incomplete
    case failed
    case inProgress = "in_progress"
}

public enum OpenAIResponsesStreamContentPart: Codable, Sendable {
    case outputText(OpenAIResponsesStreamContentPartOutputText)
    case refusal(OpenAIResponsesStreamContentPartRefusal)
    case reasoningText(OpenAIResponsesStreamContentPartReasoningText)
    case unrecognized(String)

    private enum DiscriminatorKeys: String, CodingKey { case discriminator = "type" }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DiscriminatorKeys.self)
        let discriminator = try container.decode(String.self, forKey: .discriminator)
        switch discriminator {
        case "output_text": self = .outputText(try OpenAIResponsesStreamContentPartOutputText(from: decoder))
        case "refusal": self = .refusal(try OpenAIResponsesStreamContentPartRefusal(from: decoder))
        case "reasoning_text": self = .reasoningText(try OpenAIResponsesStreamContentPartReasoningText(from: decoder))
        default: self = .unrecognized(discriminator)
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .outputText(let value): try value.encode(to: encoder)
        case .refusal(let value): try value.encode(to: encoder)
        case .reasoningText(let value): try value.encode(to: encoder)
        case .unrecognized(let discriminator):
            var container = encoder.container(keyedBy: DiscriminatorKeys.self)
            try container.encode(discriminator, forKey: .discriminator)
        }
    }
}

public struct OpenAIResponsesStreamContentPartOutputText: Codable, Sendable {
    public var type: String
    public var text: String

    public init(type: String, text: String) {
        self.type = type
        self.text = text
    }
}

public struct OpenAIResponsesStreamContentPartRefusal: Codable, Sendable {
    public var type: String
    public var refusal: String

    public init(type: String, refusal: String) {
        self.type = type
        self.refusal = refusal
    }
}

public struct OpenAIResponsesStreamContentPartReasoningText: Codable, Sendable {
    public var type: String
    public var text: String

    public init(type: String, text: String) {
        self.type = type
        self.text = text
    }
}

public enum OpenAIResponsesStreamEvent: Codable, Sendable {
    case responseCreated(OpenAIResponsesStreamEventResponseCreated)
    case responseInProgress(OpenAIResponsesStreamEventResponseInProgress)
    case responseOutputItemAdded(OpenAIResponsesStreamEventResponseOutputItemAdded)
    case responseContentPartAdded(OpenAIResponsesStreamEventResponseContentPartAdded)
    case responseOutputTextDelta(OpenAIResponsesStreamEventResponseOutputTextDelta)
    case responseOutputTextDone(OpenAIResponsesStreamEventResponseOutputTextDone)
    case responseContentPartDone(OpenAIResponsesStreamEventResponseContentPartDone)
    case responseFunctionCallArgumentsDelta(OpenAIResponsesStreamEventResponseFunctionCallArgumentsDelta)
    case responseFunctionCallArgumentsDone(OpenAIResponsesStreamEventResponseFunctionCallArgumentsDone)
    case responseReasoningSummaryTextDelta(OpenAIResponsesStreamEventResponseReasoningSummaryTextDelta)
    case responseOutputItemDone(OpenAIResponsesStreamEventResponseOutputItemDone)
    case responseCompleted(OpenAIResponsesStreamEventResponseCompleted)
    case responseIncomplete(OpenAIResponsesStreamEventResponseIncomplete)
    case responseFailed(OpenAIResponsesStreamEventResponseFailed)
    case error(OpenAIResponsesStreamEventError)
    case unrecognized(String)

    private enum DiscriminatorKeys: String, CodingKey { case discriminator = "type" }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DiscriminatorKeys.self)
        let discriminator = try container.decode(String.self, forKey: .discriminator)
        switch discriminator {
        case "response.created": self = .responseCreated(try OpenAIResponsesStreamEventResponseCreated(from: decoder))
        case "response.in_progress": self = .responseInProgress(try OpenAIResponsesStreamEventResponseInProgress(from: decoder))
        case "response.output_item.added": self = .responseOutputItemAdded(try OpenAIResponsesStreamEventResponseOutputItemAdded(from: decoder))
        case "response.content_part.added": self = .responseContentPartAdded(try OpenAIResponsesStreamEventResponseContentPartAdded(from: decoder))
        case "response.output_text.delta": self = .responseOutputTextDelta(try OpenAIResponsesStreamEventResponseOutputTextDelta(from: decoder))
        case "response.output_text.done": self = .responseOutputTextDone(try OpenAIResponsesStreamEventResponseOutputTextDone(from: decoder))
        case "response.content_part.done": self = .responseContentPartDone(try OpenAIResponsesStreamEventResponseContentPartDone(from: decoder))
        case "response.function_call_arguments.delta": self = .responseFunctionCallArgumentsDelta(try OpenAIResponsesStreamEventResponseFunctionCallArgumentsDelta(from: decoder))
        case "response.function_call_arguments.done": self = .responseFunctionCallArgumentsDone(try OpenAIResponsesStreamEventResponseFunctionCallArgumentsDone(from: decoder))
        case "response.reasoning_summary_text.delta": self = .responseReasoningSummaryTextDelta(try OpenAIResponsesStreamEventResponseReasoningSummaryTextDelta(from: decoder))
        case "response.output_item.done": self = .responseOutputItemDone(try OpenAIResponsesStreamEventResponseOutputItemDone(from: decoder))
        case "response.completed": self = .responseCompleted(try OpenAIResponsesStreamEventResponseCompleted(from: decoder))
        case "response.incomplete": self = .responseIncomplete(try OpenAIResponsesStreamEventResponseIncomplete(from: decoder))
        case "response.failed": self = .responseFailed(try OpenAIResponsesStreamEventResponseFailed(from: decoder))
        case "error": self = .error(try OpenAIResponsesStreamEventError(from: decoder))
        default: self = .unrecognized(discriminator)
        }
    }

    public func encode(to encoder: Encoder) throws {
        switch self {
        case .responseCreated(let value): try value.encode(to: encoder)
        case .responseInProgress(let value): try value.encode(to: encoder)
        case .responseOutputItemAdded(let value): try value.encode(to: encoder)
        case .responseContentPartAdded(let value): try value.encode(to: encoder)
        case .responseOutputTextDelta(let value): try value.encode(to: encoder)
        case .responseOutputTextDone(let value): try value.encode(to: encoder)
        case .responseContentPartDone(let value): try value.encode(to: encoder)
        case .responseFunctionCallArgumentsDelta(let value): try value.encode(to: encoder)
        case .responseFunctionCallArgumentsDone(let value): try value.encode(to: encoder)
        case .responseReasoningSummaryTextDelta(let value): try value.encode(to: encoder)
        case .responseOutputItemDone(let value): try value.encode(to: encoder)
        case .responseCompleted(let value): try value.encode(to: encoder)
        case .responseIncomplete(let value): try value.encode(to: encoder)
        case .responseFailed(let value): try value.encode(to: encoder)
        case .error(let value): try value.encode(to: encoder)
        case .unrecognized(let discriminator):
            var container = encoder.container(keyedBy: DiscriminatorKeys.self)
            try container.encode(discriminator, forKey: .discriminator)
        }
    }
}

public struct OpenAIResponsesStreamEventResponseCreated: Codable, Sendable {
    public var type: String
    public var response: OpenAIResponsesStreamEventResponseCreatedResponse

    public init(type: String, response: OpenAIResponsesStreamEventResponseCreatedResponse) {
        self.type = type
        self.response = response
    }
}

public struct OpenAIResponsesStreamEventResponseInProgress: Codable, Sendable {
    public var type: String
    public var response: OpenAIResponsesStreamEventResponseInProgressResponse

    public init(type: String, response: OpenAIResponsesStreamEventResponseInProgressResponse) {
        self.type = type
        self.response = response
    }
}

public struct OpenAIResponsesStreamEventResponseOutputItemAdded: Codable, Sendable {
    public var type: String
    public var outputIndex: Double
    public var item: OpenAIResponsesOutputItem

    enum CodingKeys: String, CodingKey {
        case type
        case outputIndex = "output_index"
        case item
    }

    public init(type: String, outputIndex: Double, item: OpenAIResponsesOutputItem) {
        self.type = type
        self.outputIndex = outputIndex
        self.item = item
    }
}

public struct OpenAIResponsesStreamEventResponseContentPartAdded: Codable, Sendable {
    public var type: String
    public var itemId: String
    public var outputIndex: Double
    public var contentIndex: Double
    public var part: OpenAIResponsesStreamContentPart

    enum CodingKeys: String, CodingKey {
        case type
        case itemId = "item_id"
        case outputIndex = "output_index"
        case contentIndex = "content_index"
        case part
    }

    public init(type: String, itemId: String, outputIndex: Double, contentIndex: Double, part: OpenAIResponsesStreamContentPart) {
        self.type = type
        self.itemId = itemId
        self.outputIndex = outputIndex
        self.contentIndex = contentIndex
        self.part = part
    }
}

public struct OpenAIResponsesStreamEventResponseOutputTextDelta: Codable, Sendable {
    public var type: String
    public var delta: String

    public init(type: String, delta: String) {
        self.type = type
        self.delta = delta
    }
}

public struct OpenAIResponsesStreamEventResponseOutputTextDone: Codable, Sendable {
    public var type: String
    public var itemId: String
    public var outputIndex: Double
    public var contentIndex: Double
    public var text: String

    enum CodingKeys: String, CodingKey {
        case type
        case itemId = "item_id"
        case outputIndex = "output_index"
        case contentIndex = "content_index"
        case text
    }

    public init(type: String, itemId: String, outputIndex: Double, contentIndex: Double, text: String) {
        self.type = type
        self.itemId = itemId
        self.outputIndex = outputIndex
        self.contentIndex = contentIndex
        self.text = text
    }
}

public struct OpenAIResponsesStreamEventResponseContentPartDone: Codable, Sendable {
    public var type: String
    public var itemId: String
    public var outputIndex: Double
    public var contentIndex: Double
    public var part: OpenAIResponsesStreamContentPart

    enum CodingKeys: String, CodingKey {
        case type
        case itemId = "item_id"
        case outputIndex = "output_index"
        case contentIndex = "content_index"
        case part
    }

    public init(type: String, itemId: String, outputIndex: Double, contentIndex: Double, part: OpenAIResponsesStreamContentPart) {
        self.type = type
        self.itemId = itemId
        self.outputIndex = outputIndex
        self.contentIndex = contentIndex
        self.part = part
    }
}

public struct OpenAIResponsesStreamEventResponseFunctionCallArgumentsDelta: Codable, Sendable {
    public var type: String
    public var itemId: String
    public var outputIndex: Double
    public var delta: String

    enum CodingKeys: String, CodingKey {
        case type
        case itemId = "item_id"
        case outputIndex = "output_index"
        case delta
    }

    public init(type: String, itemId: String, outputIndex: Double, delta: String) {
        self.type = type
        self.itemId = itemId
        self.outputIndex = outputIndex
        self.delta = delta
    }
}

public struct OpenAIResponsesStreamEventResponseFunctionCallArgumentsDone: Codable, Sendable {
    public var type: String
    public var itemId: String
    public var outputIndex: Double
    public var name: String
    public var arguments: String

    enum CodingKeys: String, CodingKey {
        case type
        case itemId = "item_id"
        case outputIndex = "output_index"
        case name
        case arguments
    }

    public init(type: String, itemId: String, outputIndex: Double, name: String, arguments: String) {
        self.type = type
        self.itemId = itemId
        self.outputIndex = outputIndex
        self.name = name
        self.arguments = arguments
    }
}

public struct OpenAIResponsesStreamEventResponseReasoningSummaryTextDelta: Codable, Sendable {
    public var type: String
    public var itemId: String
    public var outputIndex: Double
    public var summaryIndex: Double
    public var delta: String

    enum CodingKeys: String, CodingKey {
        case type
        case itemId = "item_id"
        case outputIndex = "output_index"
        case summaryIndex = "summary_index"
        case delta
    }

    public init(type: String, itemId: String, outputIndex: Double, summaryIndex: Double, delta: String) {
        self.type = type
        self.itemId = itemId
        self.outputIndex = outputIndex
        self.summaryIndex = summaryIndex
        self.delta = delta
    }
}

public struct OpenAIResponsesStreamEventResponseOutputItemDone: Codable, Sendable {
    public var type: String
    public var item: OpenAIResponsesOutputItem

    public init(type: String, item: OpenAIResponsesOutputItem) {
        self.type = type
        self.item = item
    }
}

public struct OpenAIResponsesStreamEventResponseCompleted: Codable, Sendable {
    public var type: String
    public var response: OpenAIResponsesStreamEventResponseCompletedResponse

    public init(type: String, response: OpenAIResponsesStreamEventResponseCompletedResponse) {
        self.type = type
        self.response = response
    }
}

public struct OpenAIResponsesStreamEventResponseIncomplete: Codable, Sendable {
    public var type: String
    public var response: OpenAIResponsesStreamEventResponseIncompleteResponse

    public init(type: String, response: OpenAIResponsesStreamEventResponseIncompleteResponse) {
        self.type = type
        self.response = response
    }
}

public struct OpenAIResponsesStreamEventResponseFailed: Codable, Sendable {
    public var type: String
    public var response: OpenAIResponsesStreamEventResponseFailedResponse

    public init(type: String, response: OpenAIResponsesStreamEventResponseFailedResponse) {
        self.type = type
        self.response = response
    }
}

public struct OpenAIResponsesStreamEventError: Codable, Sendable {
    public var type: String
    public var message: String

    public init(type: String, message: String) {
        self.type = type
        self.message = message
    }
}

public struct OpenAIResponsesStreamEventResponseCreatedResponse: Codable, Sendable {
    public var id: String

    public init(id: String) {
        self.id = id
    }
}

public struct OpenAIResponsesStreamEventResponseInProgressResponse: Codable, Sendable {
    public var id: String

    public init(id: String) {
        self.id = id
    }
}

public struct OpenAIResponsesStreamEventResponseCompletedResponse: Codable, Sendable {
    public var status: String
    public var usage: OpenAIResponsesUsage

    public init(status: String, usage: OpenAIResponsesUsage) {
        self.status = status
        self.usage = usage
    }
}

public struct OpenAIResponsesStreamEventResponseIncompleteResponse: Codable, Sendable {
    public var status: String
    public var usage: OpenAIResponsesUsage?

    public init(status: String, usage: OpenAIResponsesUsage? = nil) {
        self.status = status
        self.usage = usage
    }
}

public struct OpenAIResponsesStreamEventResponseFailedResponse: Codable, Sendable {
    public var error: OpenAIResponsesStreamEventResponseFailedResponseError?

    public init(error: OpenAIResponsesStreamEventResponseFailedResponseError? = nil) {
        self.error = error
    }
}

public struct OpenAIResponsesStreamEventResponseFailedResponseError: Codable, Sendable {
    public var message: String

    public init(message: String) {
        self.message = message
    }
}

public struct NumericRange: Codable, Sendable {
    public var min: Double?
    public var max: Double?

    public init(min: Double? = nil, max: Double? = nil) {
        self.min = min
        self.max = max
    }
}

public enum AnthropicThinkingMode: String, Codable, Sendable {
    case adaptive
    case enabled
    case disabled
}

public enum AnthropicToolChoiceOption: String, Codable, Sendable {
    case auto
    case any
    case `none` = "none"
    case tool
}

public struct AnthropicThinkingProfile: Codable, Sendable {
    public var modes: [AnthropicThinkingMode]
    public var budgetTokens: NumericRange?

    public init(modes: [AnthropicThinkingMode], budgetTokens: NumericRange? = nil) {
        self.modes = modes
        self.budgetTokens = budgetTokens
    }
}

public struct AnthropicProfile: Codable, Sendable {
    public var kind: String
    public var model: String
    public var maxTokensCeiling: Double?
    public var temperature: SwitchboardJSON?
    public var topP: SwitchboardJSON?
    public var topK: Bool?
    public var stopSequences: Bool?
    public var tools: Bool?
    public var toolChoice: [AnthropicToolChoiceOption]?
    public var thinking: SwitchboardJSON?
    public var effort: SwitchboardJSON?
    public var vision: Bool?

    public init(kind: String, model: String, maxTokensCeiling: Double? = nil, temperature: SwitchboardJSON? = nil, topP: SwitchboardJSON? = nil, topK: Bool? = nil, stopSequences: Bool? = nil, tools: Bool? = nil, toolChoice: [AnthropicToolChoiceOption]? = nil, thinking: SwitchboardJSON? = nil, effort: SwitchboardJSON? = nil, vision: Bool? = nil) {
        self.kind = kind
        self.model = model
        self.maxTokensCeiling = maxTokensCeiling
        self.temperature = temperature
        self.topP = topP
        self.topK = topK
        self.stopSequences = stopSequences
        self.tools = tools
        self.toolChoice = toolChoice
        self.thinking = thinking
        self.effort = effort
        self.vision = vision
    }
}

public enum OpenAIToolChoiceOption: String, Codable, Sendable {
    case auto
    case `none` = "none"
    case required
    case function
}

public enum OpenAIChatEffort: String, Codable, Sendable {
    case `none` = "none"
    case minimal
    case low
    case medium
    case high
    case xhigh
    case max
}

public enum OpenAIChatVerbosity: String, Codable, Sendable {
    case low
    case medium
    case high
}

public enum OpenAIResponsesEffort: String, Codable, Sendable {
    case `none` = "none"
    case minimal
    case low
    case medium
    case high
    case xhigh
    case max
}

public enum OpenAIResponsesVerbosity: String, Codable, Sendable {
    case low
    case medium
    case high
}

public struct OpenAIGenericProfile: Codable, Sendable {
    public var kind: String
    public var model: String
    public var maxTokensCeiling: Double?
    public var temperature: SwitchboardJSON?
    public var topP: SwitchboardJSON?
    public var frequencyPenalty: SwitchboardJSON?
    public var presencePenalty: SwitchboardJSON?
    public var tools: Bool?
    public var toolChoice: [OpenAIToolChoiceOption]?
    public var parallelToolCalls: Bool?
    public var responseFormat: Bool?
    public var reasoningEffort: SwitchboardJSON?
    public var verbosity: SwitchboardJSON?
    public var vision: Bool?

    public init(kind: String, model: String, maxTokensCeiling: Double? = nil, temperature: SwitchboardJSON? = nil, topP: SwitchboardJSON? = nil, frequencyPenalty: SwitchboardJSON? = nil, presencePenalty: SwitchboardJSON? = nil, tools: Bool? = nil, toolChoice: [OpenAIToolChoiceOption]? = nil, parallelToolCalls: Bool? = nil, responseFormat: Bool? = nil, reasoningEffort: SwitchboardJSON? = nil, verbosity: SwitchboardJSON? = nil, vision: Bool? = nil) {
        self.kind = kind
        self.model = model
        self.maxTokensCeiling = maxTokensCeiling
        self.temperature = temperature
        self.topP = topP
        self.frequencyPenalty = frequencyPenalty
        self.presencePenalty = presencePenalty
        self.tools = tools
        self.toolChoice = toolChoice
        self.parallelToolCalls = parallelToolCalls
        self.responseFormat = responseFormat
        self.reasoningEffort = reasoningEffort
        self.verbosity = verbosity
        self.vision = vision
    }
}

public struct OpenAIProProfile: Codable, Sendable {
    public var kind: String
    public var model: String
    public var maxTokensCeiling: Double?
    public var temperature: SwitchboardJSON?
    public var topP: SwitchboardJSON?
    public var tools: Bool?
    public var toolChoice: [OpenAIToolChoiceOption]?
    public var parallelToolCalls: Bool?
    public var reasoningEffort: SwitchboardJSON?
    public var verbosity: SwitchboardJSON?
    public var vision: Bool?

    public init(kind: String, model: String, maxTokensCeiling: Double? = nil, temperature: SwitchboardJSON? = nil, topP: SwitchboardJSON? = nil, tools: Bool? = nil, toolChoice: [OpenAIToolChoiceOption]? = nil, parallelToolCalls: Bool? = nil, reasoningEffort: SwitchboardJSON? = nil, verbosity: SwitchboardJSON? = nil, vision: Bool? = nil) {
        self.kind = kind
        self.model = model
        self.maxTokensCeiling = maxTokensCeiling
        self.temperature = temperature
        self.topP = topP
        self.tools = tools
        self.toolChoice = toolChoice
        self.parallelToolCalls = parallelToolCalls
        self.reasoningEffort = reasoningEffort
        self.verbosity = verbosity
        self.vision = vision
    }
}

public struct GoogleProfile: Codable, Sendable {
    public var kind: String
    public var model: String
    public var maxTokensCeiling: Double?
    public var temperature: SwitchboardJSON?
    public var topP: SwitchboardJSON?
    public var topK: Bool?
    public var stopSequences: Bool?
    public var tools: Bool?
    public var functionCallingModes: [GoogleFunctionCallingMode]?
    public var thinkingBudget: SwitchboardJSON?
    public var responseSchema: Bool?
    public var vision: Bool?

    public init(kind: String, model: String, maxTokensCeiling: Double? = nil, temperature: SwitchboardJSON? = nil, topP: SwitchboardJSON? = nil, topK: Bool? = nil, stopSequences: Bool? = nil, tools: Bool? = nil, functionCallingModes: [GoogleFunctionCallingMode]? = nil, thinkingBudget: SwitchboardJSON? = nil, responseSchema: Bool? = nil, vision: Bool? = nil) {
        self.kind = kind
        self.model = model
        self.maxTokensCeiling = maxTokensCeiling
        self.temperature = temperature
        self.topP = topP
        self.topK = topK
        self.stopSequences = stopSequences
        self.tools = tools
        self.functionCallingModes = functionCallingModes
        self.thinkingBudget = thinkingBudget
        self.responseSchema = responseSchema
        self.vision = vision
    }
}

public enum ProfileByKind: Codable, Sendable {
    case anthropic(AnthropicProfile)
    case openaiGeneric(OpenAIGenericProfile)
    case openaiPro(OpenAIProProfile)
    case google(GoogleProfile)
    case unrecognized(String)

    private enum CodingKeys: String, CodingKey {
        case anthropic = "anthropic"
        case openaiGeneric = "openai_generic"
        case openaiPro = "openai_pro"
        case google = "google"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let value = try container.decodeIfPresent(AnthropicProfile.self, forKey: .anthropic) {
            self = .anthropic(value); return
        }
        if let value = try container.decodeIfPresent(OpenAIGenericProfile.self, forKey: .openaiGeneric) {
            self = .openaiGeneric(value); return
        }
        if let value = try container.decodeIfPresent(OpenAIProProfile.self, forKey: .openaiPro) {
            self = .openaiPro(value); return
        }
        if let value = try container.decodeIfPresent(GoogleProfile.self, forKey: .google) {
            self = .google(value); return
        }
        let raw = try decoder.singleValueContainer().decode([String: SwitchboardJSON].self)
        self = .unrecognized(raw.keys.sorted().first ?? "")
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .anthropic(let value): try container.encode(value, forKey: .anthropic)
        case .openaiGeneric(let value): try container.encode(value, forKey: .openaiGeneric)
        case .openaiPro(let value): try container.encode(value, forKey: .openaiPro)
        case .google(let value): try container.encode(value, forKey: .google)
        case .unrecognized:
            throw EncodingError.invalidValue(self, EncodingError.Context(codingPath: encoder.codingPath, debugDescription: "Cannot encode an unrecognized ProfileByKind tag"))
        }
    }
}

public struct ModelRecordPrice: Codable, Sendable {
    public var inputMicroCentsPerMtok: Double
    public var outputMicroCentsPerMtok: Double
    public var cachedInputMicroCentsPerMtok: Double?
    public var effectiveAt: Double

    enum CodingKeys: String, CodingKey {
        case inputMicroCentsPerMtok = "input_micro_cents_per_mtok"
        case outputMicroCentsPerMtok = "output_micro_cents_per_mtok"
        case cachedInputMicroCentsPerMtok = "cached_input_micro_cents_per_mtok"
        case effectiveAt = "effective_at"
    }

    public init(inputMicroCentsPerMtok: Double, outputMicroCentsPerMtok: Double, cachedInputMicroCentsPerMtok: Double? = nil, effectiveAt: Double) {
        self.inputMicroCentsPerMtok = inputMicroCentsPerMtok
        self.outputMicroCentsPerMtok = outputMicroCentsPerMtok
        self.cachedInputMicroCentsPerMtok = cachedInputMicroCentsPerMtok
        self.effectiveAt = effectiveAt
    }
}

public struct ModelRecord: Codable, Sendable {
    public var id: String
    public var kind: ProfileByKind

    public init(id: String, kind: ProfileByKind) {
        self.id = id
        self.kind = kind
    }
}

public struct ProviderRecordSummary: Codable, Sendable {
    public var id: String
    public var displayName: String
    public var modelIds: [String]

    enum CodingKeys: String, CodingKey {
        case id
        case displayName = "display_name"
        case modelIds = "model_ids"
    }

    public init(id: String, displayName: String, modelIds: [String]) {
        self.id = id
        self.displayName = displayName
        self.modelIds = modelIds
    }
}

public enum SwitchboardJSON: Codable, Sendable, Equatable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([SwitchboardJSON])
    case object([String: SwitchboardJSON])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([SwitchboardJSON].self) { self = .array(value) }
        else if let value = try? container.decode([String: SwitchboardJSON].self) { self = .object(value) }
        else { throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unrepresentable JSON") }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }
}
