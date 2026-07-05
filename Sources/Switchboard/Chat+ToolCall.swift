import Foundation

extension Chat {
    public struct ToolCall: Codable, Sendable, Hashable {
        public let id: String
        public let type: String
        public let function: Function

        public init(id: String, function: Function) {
            self.id = id
            self.type = "function"
            self.function = function
        }

        public struct Function: Codable, Sendable, Hashable {
            public let name: String
            public let arguments: String

            public init(name: String, arguments: String) {
                self.name = name
                self.arguments = arguments
            }
        }
    }
}
