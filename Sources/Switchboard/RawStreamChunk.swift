import Foundation

public enum RawStreamChunk: Sendable, Equatable {
    case text(String)
    case paywall(PaywallEvent)
}
