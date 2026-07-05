import Foundation

public protocol Tool: Sendable {
    var name: String { get }
    var description: String { get }
    var parameters: [ToolParameter] { get }
    var requiresApproval: Bool { get }
    func execute(arguments: [String: Any]) async throws -> String
}

public struct ToolParameter: Sendable {
    public let name: String
    public let type: String
    public let description: String
    public let required: Bool

    public init(name: String, type: String, description: String, required: Bool) {
        self.name = name
        self.type = type
        self.description = description
        self.required = required
    }
}

public enum ToolError: LocalizedError {
    case missingArgument(String)
    case executionFailed(String)

    public var errorDescription: String? {
        switch self {
        case .missingArgument(let name): return "Missing argument: \(name)"
        case .executionFailed(let reason): return reason
        }
    }
}

extension [String: Any] {
    func decoded<T: Decodable>(as type: T.Type) throws -> T {
        let data = try JSONSerialization.data(withJSONObject: self)
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw ToolError.missingArgument(error.localizedDescription)
        }
    }
}
