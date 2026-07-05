import Foundation

extension Chat {
    public struct Tool: Encodable, Sendable {
        public let type: String
        public let function: Function

        public init(name: String, description: String, parameters: Parameters) {
            self.type = "function"
            self.function = Function(name: name, description: description, parameters: parameters)
        }

        public struct Function: Encodable, Sendable {
            public let name: String
            public let description: String
            public let parameters: Parameters
        }

        public struct Parameters: Encodable, Sendable {
            public let type: String
            public let properties: [String: PropertySchema]
            public let required: [String]

            public init(properties: [String: PropertySchema], required: [String] = []) {
                self.type = "object"
                self.properties = properties
                self.required = required
            }

            enum CodingKeys: String, CodingKey {
                case type, properties, required
            }

            public func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(type, forKey: .type)
                try container.encode(properties, forKey: .properties)
                if !required.isEmpty {
                    try container.encode(required, forKey: .required)
                }
            }
        }

        public struct PropertySchema: Encodable, Sendable {
            public let type: String
            public let description: String

            public init(type: String, description: String) {
                self.type = PropertySchema.normalise(type)
                self.description = description
            }

            private static func normalise(_ raw: String) -> String {
                switch raw.lowercased() {
                case "string", "number", "integer", "boolean", "object", "array", "null":
                    return raw.lowercased()
                default:
                    return raw
                }
            }
        }
    }
}
