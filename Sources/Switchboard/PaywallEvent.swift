import Foundation

public enum PaywallEvent: Sendable, Equatable {
    case outOfTokens(
        tier: Tier,
        refillAt: Date,
        monthlyBalance: Int,
        creditBalance: Int
    )

    public enum Tier: Sendable, Equatable {
        case free
        case base
        case premium
        case unknown(String)

        public var wireValue: String {
            switch self {
            case .free:           return "free"
            case .base:           return "base"
            case .premium:        return "premium"
            case .unknown(let s): return s
            }
        }

        public init(wire: String) {
            switch wire {
            case "free":    self = .free
            case "base":    self = .base
            case "premium": self = .premium
            default:        self = .unknown(wire)
            }
        }
    }
}
