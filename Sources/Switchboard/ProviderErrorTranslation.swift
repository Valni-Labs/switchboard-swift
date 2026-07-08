import Foundation

enum ProviderErrorTranslation {
    private static let nonEnvelopeBodyPreviewLimit = 256

    static func translate(_ error: SwitchboardError) -> ProviderError {
        switch error {
        case .serverError(let status, let code, let message, _):
            if code != nil {
                return mapError(status: status, envelope: envelope(from: error), rawBody: Data())
            }
            return .serverError(status: status, code: nil, message: message)
        case .transportError(let underlying):
            return .serverError(status: 0, code: nil, message: underlying.localizedDescription)
        case .decodingFailed(let underlying), .encodingFailed(let underlying):
            return .serverError(status: 0, code: nil, message: "Switchboard SDK round-trip failed: \(underlying.localizedDescription)")
        case .missingAPIKey:
            return .backendMisconfigured(code: "SWB-1001", message: "Switchboard API key missing")
        case .streamTruncated:
            return .serverError(status: 0, code: nil, message: "Switchboard stream ended before a final completion was produced")
        case .streamError(let code, let message, let detail):
            return .serverError(status: 0, code: code, message: detail.map { "\(message) (\($0))" } ?? message)
        }
    }

    private static func envelope(from error: SwitchboardError) -> ErrorEnvelope? {
        guard case let .serverError(_, code, message, context) = error, let code else { return nil }
        return ErrorEnvelope(
            code: code,
            error: message,
            model: context?.model,
            provider: context?.provider,
            spentMicros: context?.spentMicros,
            capMicros: context?.capMicros,
            retryAfterSeconds: context?.retryAfterSeconds,
        )
    }

    static func mapError(
        status: Int,
        envelope: ErrorEnvelope?,
        rawBody: Data,
    ) -> ProviderError {
        guard let envelope else {
            let message: String
            if rawBody.isEmpty {
                message = "Empty body"
            } else if let utf8 = String(data: rawBody, encoding: .utf8) {
                message = String(utf8.prefix(nonEnvelopeBodyPreviewLimit))
            } else {
                message = "Non-UTF-8 body (\(rawBody.count) bytes)"
            }
            return .serverError(status: status, code: nil, message: message)
        }
        switch envelope.code {
        case "VALNI-1001":
            return .sessionExpired

        case "SWB-1001":
            return .backendMisconfigured(code: envelope.code, message: envelope.error)

        case "SWB-1003", "SWB-1004", "VALNI-1003", "SWB-5204":
            return .rateLimited

        case "SWB-1005":
            return .costCapExceeded(
                spentMicros: envelope.spentMicros,
                capMicros: envelope.capMicros,
                retryAfterSeconds: envelope.retryAfterSeconds,
            )

        case "SWB-3001", "SWB-3005", "VALNI-3001", "SWB-5202":
            return .modelUnavailable(modelID: envelope.model)

        case "SWB-5201", "SWB-5203", "SWB-5205":
            return .upstreamUnavailable(provider: envelope.provider)

        case let code where code.hasPrefix("SWB-5"):
            return .backendMisconfigured(code: code, message: envelope.error)

        case let code where code.hasPrefix("SWB-2") || code.hasPrefix("VALNI-2"):
            return .requestInvalid(message: envelope.error)

        default:
            return .serverError(status: status, code: envelope.code, message: envelope.error)
        }
    }
}

internal struct ErrorEnvelope: Decodable {
    let code: String
    let error: String
    let model: String?
    let provider: String?
    let spentMicros: Int?
    let capMicros: Int?
    let retryAfterSeconds: Int?

    init(
        code: String,
        error: String,
        model: String? = nil,
        provider: String? = nil,
        spentMicros: Int? = nil,
        capMicros: Int? = nil,
        retryAfterSeconds: Int? = nil,
    ) {
        self.code = code
        self.error = error
        self.model = model
        self.provider = provider
        self.spentMicros = spentMicros
        self.capMicros = capMicros
        self.retryAfterSeconds = retryAfterSeconds
    }
}
