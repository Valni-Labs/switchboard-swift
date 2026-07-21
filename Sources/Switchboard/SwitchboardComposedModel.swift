import Foundation
import SwitchboardNative

public struct ComposedModel: Sendable {
    public let id: String
    public let kind: ProfileByKind
    public let price: ModelRecordPrice?

    public init(id: String, kind: ProfileByKind, price: ModelRecordPrice? = nil) {
        self.id = id
        self.kind = kind
        self.price = price
    }
}

extension ModelsPage {
    public func composed() -> [ComposedModel] {
        models.map { ComposedModel(id: $0.id, kind: $0.kind, price: prices[$0.id]) }
    }
}
