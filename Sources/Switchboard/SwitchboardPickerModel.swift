
import Foundation

public struct PickerModel: Sendable, Hashable, Decodable {
    public let id: String
    public let displayName: String
    public let contextWindow: Int
    public let maxOutputTokens: Int?
    public let inputFormats: [String]
    public let capabilities: [String]
    public let wireFormat: String

    enum CodingKeys: String, CodingKey {
        case id, capabilities
        case displayName     = "display_name"
        case contextWindow   = "context_window"
        case maxOutputTokens = "max_output_tokens"
        case inputFormats    = "input_formats"
        case wireFormat      = "wire_format"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        displayName = try container.decode(String.self, forKey: .displayName)
        contextWindow = try container.decode(Int.self, forKey: .contextWindow)
        maxOutputTokens = try container.decodeIfPresent(Int.self, forKey: .maxOutputTokens)
        inputFormats = try container.decode([String].self, forKey: .inputFormats)
        capabilities = try container.decode([String].self, forKey: .capabilities)
        wireFormat = try container.decodeIfPresent(String.self, forKey: .wireFormat) ?? WireFormat.openAICompatible
    }

    public init(
        id: String,
        displayName: String,
        contextWindow: Int,
        maxOutputTokens: Int?,
        inputFormats: [String],
        capabilities: [String],
        wireFormat: String
    ) {
        self.id = id
        self.displayName = displayName
        self.contextWindow = contextWindow
        self.maxOutputTokens = maxOutputTokens
        self.inputFormats = inputFormats
        self.capabilities = capabilities
        self.wireFormat = wireFormat
    }
}
