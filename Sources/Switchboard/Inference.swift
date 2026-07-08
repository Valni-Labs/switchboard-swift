import Foundation

public enum Inference {
    public indirect enum JSON: Codable, Sendable, Equatable {
        case null
        case bool(Bool)
        case number(Double)
        case string(String)
        case array([JSON])
        case object([String: JSON])

        public init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if container.decodeNil() {
                self = .null
            } else if let value = try? container.decode(Bool.self) {
                self = .bool(value)
            } else if let value = try? container.decode(Double.self) {
                self = .number(value)
            } else if let value = try? container.decode(String.self) {
                self = .string(value)
            } else if let value = try? container.decode([JSON].self) {
                self = .array(value)
            } else if let value = try? container.decode([String: JSON].self) {
                self = .object(value)
            } else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Value is not representable as JSON")
            }
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
}

extension Inference {
    public struct Request: Encodable, Sendable {
        public let model: Model
        public let messages: [Chat.Message]
        public let temperature: Double?
        public let maxTokens: Int?
        public let topP: Double?
        public let stream: Bool?
        public let stopSequences: [String]?
        public let tools: [Chat.Tool]?
        public let user: String?
        public let providerOptions: [String: [String: JSON]]?
        public let includeNative: Bool?

        enum CodingKeys: String, CodingKey {
            case model
            case messages
            case temperature
            case maxTokens = "max_tokens"
            case topP = "top_p"
            case stream
            case stopSequences = "stop"
            case tools
            case user
            case providerOptions = "provider_options"
            case includeNative = "include_native"
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(model.id, forKey: .model)
            try container.encode(messages, forKey: .messages)
            try container.encodeIfPresent(temperature, forKey: .temperature)
            try container.encodeIfPresent(maxTokens, forKey: .maxTokens)
            try container.encodeIfPresent(topP, forKey: .topP)
            try container.encodeIfPresent(stream, forKey: .stream)
            try container.encodeIfPresent(stopSequences, forKey: .stopSequences)
            try container.encodeIfPresent(tools, forKey: .tools)
            try container.encodeIfPresent(user, forKey: .user)
            try container.encodeIfPresent(providerOptions, forKey: .providerOptions)
            try container.encodeIfPresent(includeNative, forKey: .includeNative)
        }

        public init(
            model: Model,
            messages: [Chat.Message],
            temperature: Double? = nil,
            maxTokens: Int? = nil,
            topP: Double? = nil,
            stream: Bool? = nil,
            stopSequences: [String]? = nil,
            tools: [Chat.Tool]? = nil,
            user: String? = nil,
            providerOptions: [String: [String: JSON]]? = nil,
            includeNative: Bool? = nil,
        ) {
            self.model = model
            self.messages = messages
            self.temperature = temperature
            self.maxTokens = maxTokens
            self.topP = topP
            self.stream = stream
            self.stopSequences = stopSequences
            self.tools = tools
            self.user = user
            self.providerOptions = providerOptions
            self.includeNative = includeNative
        }
    }
}

extension Inference {
    public enum Frame: Sendable, Equatable {
        case textDelta(text: String)
        case reasoningDelta(text: String)
        case toolCall(id: String, name: String, argumentsJSON: String)
        case usage(inputTokens: Int, outputTokens: Int)
        case done(finishReason: String)
        case native(JSON)
        case error(code: String, message: String, detail: String?)

        private struct Wire: Decodable {
            let type: String
            let text: String?
            let id: String?
            let name: String?
            let argumentsJson: String?
            let inputTokens: Int?
            let outputTokens: Int?
            let finishReason: String?
            let native: JSON?
            let code: String?
            let error: String?
            let detail: String?

            enum CodingKeys: String, CodingKey {
                case type, text, id, name, native, code, error, detail
                case argumentsJson = "arguments_json"
                case inputTokens = "input_tokens"
                case outputTokens = "output_tokens"
                case finishReason = "finish_reason"
            }
        }

        public static func parse(_ data: Data, decoder: JSONDecoder = JSONDecoder()) throws -> Frame? {
            let wire = try decoder.decode(Wire.self, from: data)
            switch wire.type {
            case "text_delta":
                guard let text = wire.text else { return nil }
                return .textDelta(text: text)
            case "reasoning_delta":
                guard let text = wire.text else { return nil }
                return .reasoningDelta(text: text)
            case "tool_call":
                guard let id = wire.id, let name = wire.name, let argumentsJSON = wire.argumentsJson else { return nil }
                return .toolCall(id: id, name: name, argumentsJSON: argumentsJSON)
            case "usage":
                guard let inputTokens = wire.inputTokens, let outputTokens = wire.outputTokens else { return nil }
                return .usage(inputTokens: inputTokens, outputTokens: outputTokens)
            case "done":
                guard let finishReason = wire.finishReason else { return nil }
                return .done(finishReason: finishReason)
            case "native":
                guard let native = wire.native else { return nil }
                return .native(native)
            case "error":
                guard let code = wire.code, let message = wire.error else { return nil }
                return .error(code: code, message: message, detail: wire.detail)
            default:
                return nil
            }
        }
    }
}

extension Inference {
    public struct Response: Decodable, Sendable {
        public struct ToolCall: Decodable, Sendable, Equatable {
            public struct Function: Decodable, Sendable, Equatable {
                public let name: String
                public let arguments: String
            }

            public let id: String
            public let function: Function
        }

        public struct Message: Decodable, Sendable {
            public let role: String
            public let content: String
            public let toolCalls: [ToolCall]?
            public let nativeParts: [JSON]?

            enum CodingKeys: String, CodingKey {
                case role, content
                case toolCalls = "tool_calls"
                case nativeParts = "native_parts"
            }
        }

        public struct Choice: Decodable, Sendable {
            public let message: Message
            public let finishReason: String?

            enum CodingKeys: String, CodingKey {
                case message
                case finishReason = "finish_reason"
            }
        }

        public struct Usage: Decodable, Sendable, Equatable {
            public let inputTokens: Int
            public let outputTokens: Int

            enum CodingKeys: String, CodingKey {
                case inputTokens = "prompt_tokens"
                case outputTokens = "completion_tokens"
            }
        }

        public let id: String?
        public let model: String?
        public let choices: [Choice]
        public let usage: Usage?
        public let native: JSON?
    }
}
