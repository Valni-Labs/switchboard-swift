import Foundation

struct GenericWireMessage: Encodable {
    let role: String
    let content: WireContent
    let toolCallID: String?
    let toolCalls: [Chat.ToolCall]?

    enum CodingKeys: String, CodingKey {
        case role
        case content
        case toolCallID = "tool_call_id"
        case toolCalls = "tool_calls"
    }

    init(from message: ChatMessage) {
        self.role = message.role.rawValue
        switch message.content {
        case .text(let text):
            self.content = .text(text)
        case .blocks(let blocks):
            self.content = .blocks(blocks.map(WireBlock.init(from:)))
        }
        self.toolCallID = message.toolCallID
        self.toolCalls = message.toolCalls
    }

    enum WireContent: Encodable {
        case text(String)
        case blocks([WireBlock])

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .text(let s):
                try container.encode(s)
            case .blocks(let blocks):
                try container.encode(blocks)
            }
        }
    }

    enum WireBlock: Encodable {
        case text(String)
        case imageURL(String)

        init(from block: ContentBlock) {
            switch block {
            case .text(let text):
                self = .text(text)
            case .image(let image):
                self = .imageURL(image.dataURL)
            }
        }

        private enum CodingKeys: String, CodingKey {
            case type
            case text
            case imageURL = "image_url"
        }

        private struct ImageURLPayload: Encodable {
            let url: String
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .text(let text):
                try container.encode("text", forKey: .type)
                try container.encode(text, forKey: .text)
            case .imageURL(let url):
                try container.encode("image_url", forKey: .type)
                try container.encode(ImageURLPayload(url: url), forKey: .imageURL)
            }
        }
    }
}
