
import XCTest
@testable import Switchboard

final class SwitchboardProviderErrorMappingTests: XCTestCase {

    func testFirebaseAuthFailureMapsToSessionExpired() {
        let result = ProviderErrorTranslation.mapError(
            status: 401,
            envelope: envelope(code: "VALNI-1001", error: "Authentication required"),
            rawBody: Data(),
        )
        guard case .sessionExpired = result else {
            return XCTFail("expected .sessionExpired, got \(result)")
        }
    }

    func testSwitchboardAuthFailureMapsToBackendMisconfigured() {
        let result = ProviderErrorTranslation.mapError(
            status: 401,
            envelope: envelope(code: "SWB-1001", error: "Authentication required"),
            rawBody: Data(),
        )
        guard case let .backendMisconfigured(code, message) = result else {
            return XCTFail("expected .backendMisconfigured, got \(result)")
        }
        XCTAssertEqual(code, "SWB-1001")
        XCTAssertEqual(message, "Authentication required")
    }

    func testRateLimitCodesMapToRateLimited() {
        for code in ["SWB-1003", "SWB-1004", "VALNI-1003", "SWB-5204"] {
            let result = ProviderErrorTranslation.mapError(
                status: 429,
                envelope: envelope(code: code, error: "Too many requests"),
                rawBody: Data(),
            )
            guard case .rateLimited = result else {
                return XCTFail("\(code) expected .rateLimited, got \(result)")
            }
        }
    }

    func testCostCapExceededCarriesSpentCapAndRetryAfter() {
        let result = ProviderErrorTranslation.mapError(
            status: 429,
            envelope: envelope(
                code: "SWB-1005",
                error: "Monthly cost cap exceeded",
                spentMicros: 10_300_000_000,
                capMicros: 10_000_000_000,
                retryAfterSeconds: 1_036_800,
            ),
            rawBody: Data(),
        )
        guard case let .costCapExceeded(spent, cap, retry) = result else {
            return XCTFail("expected .costCapExceeded, got \(result)")
        }
        XCTAssertEqual(spent, 10_300_000_000)
        XCTAssertEqual(cap, 10_000_000_000)
        XCTAssertEqual(retry, 1_036_800)
    }

    func testCostCapExceededTolerantOfMissingContext() {
        let result = ProviderErrorTranslation.mapError(
            status: 429,
            envelope: envelope(code: "SWB-1005", error: "Monthly cost cap exceeded"),
            rawBody: Data(),
        )
        guard case let .costCapExceeded(spent, cap, retry) = result else {
            return XCTFail("expected .costCapExceeded, got \(result)")
        }
        XCTAssertNil(spent)
        XCTAssertNil(cap)
        XCTAssertNil(retry)
    }

    func testModelUnavailableCodesCarryModelID() {
        for code in ["SWB-3001", "VALNI-3001", "SWB-5202"] {
            let result = ProviderErrorTranslation.mapError(
                status: 404,
                envelope: envelope(code: code, error: "Unknown model", model: "fixture-model-unknown"),
                rawBody: Data(),
            )
            guard case let .modelUnavailable(modelID) = result else {
                return XCTFail("\(code) expected .modelUnavailable, got \(result)")
            }
            XCTAssertEqual(modelID, "fixture-model-unknown")
        }
    }

    func testDeprecatedModelCodeMapsToModelUnavailable() {
        let result = ProviderErrorTranslation.mapError(
            status: 410,
            envelope: envelope(code: "SWB-3005", error: "Model deprecated", model: "fixture-model-retired"),
            rawBody: Data(),
        )
        guard case let .modelUnavailable(modelID) = result else {
            return XCTFail("expected .modelUnavailable, got \(result)")
        }
        XCTAssertEqual(modelID, "fixture-model-retired")
    }

    func testModelUnavailableCarriesNilWhenServerOmitsModel() {
        let result = ProviderErrorTranslation.mapError(
            status: 404,
            envelope: envelope(code: "SWB-3001", error: "Unknown model"),
            rawBody: Data(),
        )
        guard case let .modelUnavailable(modelID) = result else {
            return XCTFail("expected .modelUnavailable, got \(result)")
        }
        XCTAssertNil(modelID)
        let description = (result as LocalizedError).errorDescription ?? ""
        XCTAssertFalse(description.contains("unknown"), "description should not leak the placeholder")
    }

    func testUpstreamProviderCodesMapToUpstreamUnavailable() {
        for code in ["SWB-5201", "SWB-5203", "SWB-5205"] {
            let result = ProviderErrorTranslation.mapError(
                status: 502,
                envelope: envelope(code: code, error: "Upstream broken", provider: "anthropic"),
                rawBody: Data(),
            )
            guard case let .upstreamUnavailable(provider) = result else {
                return XCTFail("\(code) expected .upstreamUnavailable, got \(result)")
            }
            XCTAssertEqual(provider, "anthropic")
        }
    }

    func testCatalogAndConfigCodesMapToBackendMisconfigured() {
        for code in ["SWB-5001", "SWB-5002", "SWB-5003", "SWB-5101"] {
            let result = ProviderErrorTranslation.mapError(
                status: 503,
                envelope: envelope(code: code, error: "Backend issue"),
                rawBody: Data(),
            )
            guard case let .backendMisconfigured(returnedCode, message) = result else {
                return XCTFail("\(code) expected .backendMisconfigured, got \(result)")
            }
            XCTAssertEqual(returnedCode, code)
            XCTAssertEqual(message, "Backend issue")
        }
    }

    func testValidationCodesMapToRequestInvalid() {
        for code in ["SWB-2001", "SWB-2003", "VALNI-2001", "VALNI-2004"] {
            let result = ProviderErrorTranslation.mapError(
                status: 400,
                envelope: envelope(code: code, error: "Bad request"),
                rawBody: Data(),
            )
            guard case let .requestInvalid(message) = result else {
                return XCTFail("\(code) expected .requestInvalid, got \(result)")
            }
            XCTAssertEqual(message, "Bad request")
        }
    }

    func testUnknownCodeMapsToServerError() {
        let result = ProviderErrorTranslation.mapError(
            status: 418,
            envelope: envelope(code: "SWB-9999", error: "I'm a teapot"),
            rawBody: Data(),
        )
        guard case let .serverError(status, code, message) = result else {
            return XCTFail("expected .serverError, got \(result)")
        }
        XCTAssertEqual(status, 418)
        XCTAssertEqual(code, "SWB-9999")
        XCTAssertEqual(message, "I'm a teapot")
    }

    func testMissingEnvelopeFallsBackToBodyPreview() {
        let body = Data("Cloudflare 1101: worker exception".utf8)
        let result = ProviderErrorTranslation.mapError(
            status: 500,
            envelope: nil,
            rawBody: body,
        )
        guard case let .serverError(status, code, message) = result else {
            return XCTFail("expected .serverError, got \(result)")
        }
        XCTAssertEqual(status, 500)
        XCTAssertNil(code)
        XCTAssertTrue(message.contains("Cloudflare 1101"))
    }

    func testMissingEnvelopeWithEmptyBodyReportsEmptyBody() {
        let result = ProviderErrorTranslation.mapError(
            status: 502,
            envelope: nil,
            rawBody: Data(),
        )
        guard case let .serverError(_, _, message) = result else {
            return XCTFail("expected .serverError, got \(result)")
        }
        XCTAssertEqual(message, "Empty body")
    }

    func testMissingEnvelopeWithNonUTF8BodyDistinguishesFromEmpty() {
        let nonUTF8 = Data([0x80, 0x81, 0x82, 0xFF])
        let result = ProviderErrorTranslation.mapError(
            status: 502,
            envelope: nil,
            rawBody: nonUTF8,
        )
        guard case let .serverError(_, _, message) = result else {
            return XCTFail("expected .serverError, got \(result)")
        }
        XCTAssertNotEqual(message, "Empty body")
        XCTAssertTrue(message.contains("Non-UTF-8"), "got: \(message)")
        XCTAssertTrue(message.contains("4 bytes"), "got: \(message)")
    }

    func testTranslatePreservesMessageWhenSDKCouldNotParseEnvelope() {
        let result = ProviderErrorTranslation.translate(
            .serverError(
                status: 502,
                code: nil,
                message: "Cloudflare 1101: worker exception",
                context: nil,
            )
        )
        guard case let .serverError(status, code, message) = result else {
            return XCTFail("expected .serverError, got \(result)")
        }
        XCTAssertEqual(status, 502)
        XCTAssertNil(code)
        XCTAssertEqual(message, "Cloudflare 1101: worker exception",
                       "should pass the SDK's message through verbatim, not collapse to 'Empty body'")
    }

    func testTranslateDispatchesToMapErrorWhenCodePresent() {
        let result = ProviderErrorTranslation.translate(
            .serverError(
                status: 429,
                code: "SWB-1003",
                message: "Rate limit exceeded",
                context: nil,
            )
        )
        guard case .rateLimited = result else {
            return XCTFail("expected .rateLimited, got \(result)")
        }
    }

    func testTranslateMissingAPIKeyMapsToBackendMisconfigured() {
        let result = ProviderErrorTranslation.translate(.missingAPIKey)
        guard case let .backendMisconfigured(code, _) = result else {
            return XCTFail("expected .backendMisconfigured, got \(result)")
        }
        XCTAssertEqual(code, "SWB-1001")
    }
}

private func envelope(
    code: String,
    error: String,
    model: String? = nil,
    provider: String? = nil,
    spentMicros: Int? = nil,
    capMicros: Int? = nil,
    retryAfterSeconds: Int? = nil,
) -> ServerErrorEnvelope {
    let payload: [String: Any] = [
        "code": code,
        "error": error,
        "model": model as Any,
        "provider": provider as Any,
        "spentMicros": spentMicros as Any,
        "capMicros": capMicros as Any,
        "retryAfterSeconds": retryAfterSeconds as Any,
    ].compactMapValues { value in
        if value is NSNull { return nil }
        return value
    }
    let data = try! JSONSerialization.data(withJSONObject: payload)
    return try! JSONDecoder().decode(ServerErrorEnvelope.self, from: data)
}
