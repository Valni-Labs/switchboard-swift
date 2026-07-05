import Foundation

public struct ChatMessage: Sendable {
    public enum Role: String, Sendable {
        case system
        case user
        case assistant
        case tool
    }

    public let role: Role
    public let content: Content
    public let toolCallID: String?
    public let toolCalls: [Chat.ToolCall]?

    public init(role: Role, content: Content, toolCallID: String? = nil, toolCalls: [Chat.ToolCall]? = nil) {
        precondition(toolCalls == nil || role == .assistant, "toolCalls are only valid on assistant messages")
        precondition((role == .tool) == (toolCallID != nil), "toolCallID is required exactly when role is tool")
        self.role = role
        self.content = content
        self.toolCallID = toolCallID
        self.toolCalls = toolCalls
    }

    public init(role: Role, text: String) {
        precondition(role != .tool, "use ChatMessage.tool(callID:result:) to construct tool messages")
        self.init(role: role, content: .text(text))
    }

    public static func tool(callID: String, result: String) -> ChatMessage {
        .init(role: .tool, content: .text(result), toolCallID: callID)
    }

    public var hasNonTextContent: Bool {
        switch content {
        case .text:
            return false
        case .blocks(let blocks):
            return blocks.contains { if case .text = $0 { return false } else { return true } }
        }
    }
}

public enum Content: Sendable {
    case text(String)
    case blocks([ContentBlock])
}

public enum ContentBlock: Sendable {
    case text(String)
    case image(ImageData)
}

public struct ImageData: Sendable, Equatable {
    public let mediaType: String
    public let base64: String

    public init(mediaType: String, base64: String) {
        self.mediaType = mediaType
        self.base64 = base64
    }

    public var dataURL: String {
        "data:\(mediaType);base64,\(base64)"
    }
}
