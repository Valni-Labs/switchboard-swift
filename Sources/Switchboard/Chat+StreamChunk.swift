import Foundation

extension Chat {
    public struct StreamChunk: Decodable, Sendable {
        public struct Choice: Decodable, Sendable {
            public struct Delta: Decodable, Sendable {
                public let role: Message.Role?
                public let content: String?
                public let toolCalls: [ToolCallDelta]?

                enum CodingKeys: String, CodingKey {
                    case role, content
                    case toolCalls = "tool_calls"
                }
            }
            public let index: Int
            public let delta: Delta
            public let finishReason: String?

            enum CodingKeys: String, CodingKey {
                case index, delta
                case finishReason = "finish_reason"
            }
        }

        public let id: String
        public let model: String?
        public let choices: [Choice]
        public let usage: Response.Usage?
    }

    public struct ToolCallDelta: Decodable, Sendable {
        public let index: Int
        public let id: String?
        public let type: String?
        public let function: FunctionDelta?

        public struct FunctionDelta: Decodable, Sendable {
            public let name: String?
            public let arguments: String?
        }
    }
}
