import Foundation

extension Chat {
    public struct Message: Codable, Sendable, Hashable {
        public enum Role: String, Codable, Sendable {
            case system, user, assistant
            case tool
        }

        public let role: Role
        public let content: Content
        public let toolCallId: String?
        public let toolCalls: [ToolCall]?

        public init(
            role: Role,
            content: Content,
            toolCallId: String? = nil,
            toolCalls: [ToolCall]? = nil,
        ) {
            self.role = role
            self.content = content
            self.toolCallId = toolCallId
            self.toolCalls = toolCalls
        }

        public static func system(_ text: String) -> Message    { .init(role: .system,    content: .text(text)) }
        public static func user(_ text: String) -> Message      { .init(role: .user,      content: .text(text)) }
        public static func assistant(_ text: String) -> Message { .init(role: .assistant, content: .text(text)) }
        public static func user(parts: [Content.Part]) -> Message {
            .init(role: .user, content: .parts(parts))
        }
        public static func tool(callId: String, result: String) -> Message {
            .init(role: .tool, content: .text(result), toolCallId: callId)
        }

        enum CodingKeys: String, CodingKey {
            case role, content
            case toolCallId = "tool_call_id"
            case toolCalls  = "tool_calls"
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            self.role = try container.decode(Role.self, forKey: .role)
            if let decoded = try container.decodeIfPresent(Content.self, forKey: .content) {
                self.content = decoded
            } else if self.role == .assistant {
                self.content = .text("")
            } else {
                throw DecodingError.dataCorruptedError(
                    forKey: .content,
                    in: container,
                    debugDescription: "`content` is required for role .\(self.role.rawValue)",
                )
            }
            self.toolCallId = try container.decodeIfPresent(String.self, forKey: .toolCallId)
            self.toolCalls  = try container.decodeIfPresent([ToolCall].self, forKey: .toolCalls)
        }

        public func encode(to encoder: Encoder) throws {
            if role == .tool && toolCallId == nil {
                throw EncodingError.invalidValue(role, .init(
                    codingPath: encoder.codingPath,
                    debugDescription: "`toolCallId` is required when role is .tool",
                ))
            }
            if let toolCallId, role != .tool {
                throw EncodingError.invalidValue(toolCallId, .init(
                    codingPath: encoder.codingPath,
                    debugDescription: "`toolCallId` is only valid when role is .tool",
                ))
            }
            if let toolCalls, role != .assistant {
                throw EncodingError.invalidValue(toolCalls, .init(
                    codingPath: encoder.codingPath,
                    debugDescription: "`toolCalls` is only valid when role is .assistant",
                ))
            }

            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(role, forKey: .role)
            try container.encode(content, forKey: .content)
            try container.encodeIfPresent(toolCallId, forKey: .toolCallId)
            try container.encodeIfPresent(toolCalls, forKey: .toolCalls)
        }
    }
}
