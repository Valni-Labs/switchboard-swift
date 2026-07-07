
import Foundation

public struct SupportedProvider: Sendable, Hashable {
    public let id: String

    public init(_ id: String) {
        self.id = id
    }
}
