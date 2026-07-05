import Foundation

extension Chat {
    public struct Response: Decodable, Sendable {
        public struct Choice: Decodable, Sendable {
            public let index: Int
            public let message: Message
            public let finishReason: String?

            enum CodingKeys: String, CodingKey {
                case index, message
                case finishReason = "finish_reason"
            }
        }

        public struct Usage: Decodable, Sendable, Equatable {
            public let promptTokens: Int
            public let completionTokens: Int
            public let totalTokens: Int
            public let cacheCreationTokens: Int
            public let cacheReadTokens: Int
            public let reasoningTokens: Int

            enum CodingKeys: String, CodingKey {
                case promptTokens         = "prompt_tokens"
                case completionTokens     = "completion_tokens"
                case totalTokens          = "total_tokens"
                case cacheCreationTokens  = "cache_creation_tokens"
                case cacheReadTokens      = "cache_read_tokens"
                case reasoningTokens      = "reasoning_tokens"
            }

            public init(
                promptTokens: Int,
                completionTokens: Int,
                totalTokens: Int,
                cacheCreationTokens: Int = 0,
                cacheReadTokens: Int = 0,
                reasoningTokens: Int = 0,
            ) {
                self.promptTokens = promptTokens
                self.completionTokens = completionTokens
                self.totalTokens = totalTokens
                self.cacheCreationTokens = cacheCreationTokens
                self.cacheReadTokens = cacheReadTokens
                self.reasoningTokens = reasoningTokens
            }

            public init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                self.promptTokens     = try container.decode(Int.self, forKey: .promptTokens)
                self.completionTokens = try container.decode(Int.self, forKey: .completionTokens)
                self.totalTokens      = try container.decode(Int.self, forKey: .totalTokens)
                self.cacheCreationTokens = try container.decodeIfPresent(Int.self, forKey: .cacheCreationTokens) ?? 0
                self.cacheReadTokens     = try container.decodeIfPresent(Int.self, forKey: .cacheReadTokens) ?? 0
                self.reasoningTokens     = try container.decodeIfPresent(Int.self, forKey: .reasoningTokens) ?? 0
            }
        }

        public let id: String
        public let model: String
        public let choices: [Choice]
        public let usage: Usage?

        public var content: String? {
            choices.first?.message.content.text
        }
    }
}
