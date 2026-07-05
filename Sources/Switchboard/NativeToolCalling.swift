import Foundation

public enum ToolCallMode: String, Sendable, Codable, CaseIterable {
    case prompt
    case native
}

public enum NativeStreamChunk: Sendable {
    case text(String)

    case toolCall(id: String, name: String, argumentsJSON: String)

    case paywall(PaywallEvent)
}

public struct ToolSchema: Sendable {
    public let name: String
    public let description: String
    public let parameters: [ToolParameter]

    public init(name: String, description: String, parameters: [ToolParameter]) {
        self.name = name
        self.description = description
        self.parameters = parameters
    }
}

public enum NativeToolCallError: LocalizedError {
    case notSupported

    public var errorDescription: String? {
        switch self {
        case .notSupported:
            return "This provider does not support native tool calling."
        }
    }
}
