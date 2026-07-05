
import Foundation

public struct Model: Sendable, Hashable, ExpressibleByStringLiteral {
    public let id: String

    public init(_ id: String) {
        self.id = id
    }

    public init(stringLiteral value: StringLiteralType) {
        self.id = value
    }
}
