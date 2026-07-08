
import Foundation

public enum SwitchboardError: Error, LocalizedError, Sendable {
    case serverError(status: Int, code: String?, message: String, context: ServerErrorContext?)

    case decodingFailed(underlying: Error)

    case encodingFailed(underlying: Error)

    case transportError(underlying: Error)

    case missingAPIKey

    case streamTruncated

    case streamError(code: String, message: String, detail: String?)

    public var errorDescription: String? {
        switch self {
        case .serverError(let status, let code, let message, _):
            if let code {
                return "Switchboard \(status) \(code): \(message)"
            }
            return "Switchboard \(status): \(message)"
        case .decodingFailed(let underlying):
            return "Switchboard response decode failed: \(underlying.localizedDescription)"
        case .encodingFailed(let underlying):
            return "Switchboard request body encode failed: \(underlying.localizedDescription)"
        case .transportError(let underlying):
            return "Switchboard request failed: \(underlying.localizedDescription)"
        case .missingAPIKey:
            return "Switchboard.Client was constructed with an empty API key."
        case .streamTruncated:
            return "Switchboard stream ended before a final completion was produced."
        case .streamError(let code, let message, let detail):
            if let detail {
                return "Switchboard stream error \(code): \(message) (\(detail))"
            }
            return "Switchboard stream error \(code): \(message)"
        }
    }
}

public struct ServerErrorContext: Sendable, Equatable, Decodable {
    public let model: String?
    public let provider: String?
    public let spentMicros: Int?
    public let capMicros: Int?
    public let retryAfterSeconds: Int?

    public init(
        model: String? = nil,
        provider: String? = nil,
        spentMicros: Int? = nil,
        capMicros: Int? = nil,
        retryAfterSeconds: Int? = nil,
    ) {
        self.model = model
        self.provider = provider
        self.spentMicros = spentMicros
        self.capMicros = capMicros
        self.retryAfterSeconds = retryAfterSeconds
    }
}
