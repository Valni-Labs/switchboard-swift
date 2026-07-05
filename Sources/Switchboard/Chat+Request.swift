import Foundation

extension Chat {
    public struct Request: Encodable, Sendable {
        public let model: Model
        public let messages: [Message]
        public let temperature: Double?
        public let maxTokens: Int?
        public let topP: Double?
        public let stream: Bool?
        public let stopSequences: [String]?
        public let tools: [Tool]?
        public let user: String?

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
        }

        public init(
            model: Model,
            messages: [Message],
            temperature: Double? = nil,
            maxTokens: Int? = nil,
            topP: Double? = nil,
            stream: Bool? = nil,
            stopSequences: [String]? = nil,
            tools: [Tool]? = nil,
            user: String? = nil,
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
            if let user {
                guard !user.isEmpty else {
                    throw EncodingError.invalidValue(user, .init(
                        codingPath: encoder.codingPath,
                        debugDescription: "`user` must be non-empty; pass nil to skip attribution",
                    ))
                }
                guard user.count <= 256 else {
                    throw EncodingError.invalidValue(user, .init(
                        codingPath: encoder.codingPath,
                        debugDescription: "`user` must be 256 characters or fewer (got \(user.count))",
                    ))
                }
                try container.encode(user, forKey: .user)
            }
        }
    }
}
