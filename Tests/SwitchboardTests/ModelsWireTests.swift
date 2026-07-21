
import XCTest
@testable import Switchboard

final class ModelsWireTests: XCTestCase {

    static let pageFixture = """
    {
      "models": [
        {
          "id": "claude-opus-4-8",
          "kind": {
            "anthropic": {
              "kind": "anthropic",
              "model": "claude-opus-4-8",
              "maxTokensCeiling": 32000,
              "tools": true
            }
          }
        },
        {
          "id": "gemini-3-flash",
          "kind": {
            "google": {
              "kind": "google",
              "model": "gemini-3-flash"
            }
          }
        }
      ],
      "prices": {
        "claude-opus-4-8": {
          "input_micro_cents_per_mtok": 500000000,
          "output_micro_cents_per_mtok": 2500000000,
          "cached_input_micro_cents_per_mtok": 50000000,
          "effective_at": 1783209600
        }
      }
    }
    """

    func testModelsReturnsDecodedPage() async throws {
        let stub = stubURLSession(statusCode: 200, body: Self.pageFixture)
        let client = Client(apiKey: "swb_test", urlSession: stub)
        let page = try await client.models()
        XCTAssertEqual(page.models.count, 2)
        let opus = try XCTUnwrap(page.models.first)
        XCTAssertEqual(opus.id, "claude-opus-4-8")
        let flash = try XCTUnwrap(page.models.last)
        XCTAssertEqual(flash.id, "gemini-3-flash")
        XCTAssertEqual(page.prices.count, 1)
        let opusPrice = try XCTUnwrap(page.prices["claude-opus-4-8"])
        XCTAssertEqual(opusPrice.inputMicroCentsPerMtok, 500000000)
        XCTAssertEqual(opusPrice.outputMicroCentsPerMtok, 2500000000)
        XCTAssertEqual(opusPrice.cachedInputMicroCentsPerMtok, 50000000)
        XCTAssertEqual(opusPrice.effectiveAt, 1783209600)
        XCTAssertNil(page.prices["gemini-3-flash"])
    }

    func testProfileByKindDecodesTaggedProfiles() async throws {
        let stub = stubURLSession(statusCode: 200, body: Self.pageFixture)
        let client = Client(apiKey: "swb_test", urlSession: stub)
        let page = try await client.models()
        let opus = try XCTUnwrap(page.models.first)
        switch opus.kind {
        case .anthropic(let profile):
            XCTAssertEqual(profile.kind, "anthropic")
            XCTAssertEqual(profile.model, "claude-opus-4-8")
            XCTAssertEqual(profile.maxTokensCeiling, 32000)
            XCTAssertEqual(profile.tools, true)
        case .openaiGeneric, .openaiPro, .google, .unrecognized:
            XCTFail("expected .anthropic kind, got \(opus.kind)")
        }
        let flash = try XCTUnwrap(page.models.last)
        switch flash.kind {
        case .google(let profile):
            XCTAssertEqual(profile.kind, "google")
            XCTAssertEqual(profile.model, "gemini-3-flash")
        case .anthropic, .openaiGeneric, .openaiPro, .unrecognized:
            XCTFail("expected .google kind, got \(flash.kind)")
        }
    }

    func testComposedJoinsPricesById() async throws {
        let stub = stubURLSession(statusCode: 200, body: Self.pageFixture)
        let client = Client(apiKey: "swb_test", urlSession: stub)
        let composed = try await client.models().composed()
        XCTAssertEqual(composed.count, 2)
        let opus = try XCTUnwrap(composed.first)
        XCTAssertEqual(opus.id, "claude-opus-4-8")
        guard case .anthropic = opus.kind else {
            XCTFail("expected .anthropic kind, got \(opus.kind)")
            return
        }
        let opusPrice = try XCTUnwrap(opus.price)
        XCTAssertEqual(opusPrice.inputMicroCentsPerMtok, 500000000)
        let flash = try XCTUnwrap(composed.last)
        XCTAssertEqual(flash.id, "gemini-3-flash")
        XCTAssertNil(flash.price)
    }

    func testModelsSendsGETWithBearerAuthorizationHeader() async throws {
        var captured: URLRequest?
        let stub = stubURLSession(
            statusCode: 200,
            body: """
            {"models":[],"prices":{}}
            """,
            requestInspector: { captured = $0 },
        )
        let client = Client(
            apiKey: "swb_abcdef",
            baseURL: URL(string: "https://switchboard.example.com")!,
            urlSession: stub,
        )
        _ = try await client.models()
        XCTAssertEqual(captured?.httpMethod, "GET")
        XCTAssertEqual(captured?.value(forHTTPHeaderField: "Authorization"), "Bearer swb_abcdef")
        XCTAssertEqual(captured?.url?.absoluteString, "https://switchboard.example.com/v1/models")
    }

    func testModelsThrowsServerErrorWithEnvelope() async {
        let stub = stubURLSession(
            statusCode: 401,
            body: """
            {"code":"SWB-1001","error":"Authentication required"}
            """,
        )
        let client = Client(apiKey: "swb_test", urlSession: stub)
        do {
            _ = try await client.models()
            XCTFail("expected throw")
        } catch let error as SwitchboardError {
            switch error {
            case .serverError(let status, let code, let message, _):
                XCTAssertEqual(status, 401)
                XCTAssertEqual(code, "SWB-1001")
                XCTAssertEqual(message, "Authentication required")
            default:
                XCTFail("expected .serverError, got \(error)")
            }
        } catch {
            XCTFail("unexpected error type: \(error)")
        }
    }

    func testModelsThrowsMissingAPIKey() async {
        let stub = stubURLSession(statusCode: 200, body: """
        {"models":[],"prices":{}}
        """)
        let client = Client(apiKey: "", urlSession: stub)
        do {
            _ = try await client.models()
            XCTFail("expected throw")
        } catch let error as SwitchboardError {
            if case .missingAPIKey = error { } else {
                XCTFail("expected .missingAPIKey, got \(error)")
            }
        } catch {
            XCTFail("unexpected error type: \(error)")
        }
    }

    func testModelsThrowsDecodingFailedOnMalformedBody() async {
        let stub = stubURLSession(
            statusCode: 200,
            body: """
            {"models":[{"id":"test-model-large"}],"prices":{}}
            """,
        )
        let client = Client(apiKey: "swb_test", urlSession: stub)
        do {
            _ = try await client.models()
            XCTFail("expected throw")
        } catch let error as SwitchboardError {
            if case .decodingFailed = error { } else {
                XCTFail("expected .decodingFailed, got \(error)")
            }
        } catch {
            XCTFail("unexpected error type: \(error)")
        }
    }

    func testModelsThrowsDecodingFailedOnMissingPrices() async {
        let stub = stubURLSession(
            statusCode: 200,
            body: """
            {"models":[]}
            """,
        )
        let client = Client(apiKey: "swb_test", urlSession: stub)
        do {
            _ = try await client.models()
            XCTFail("expected throw")
        } catch let error as SwitchboardError {
            if case .decodingFailed = error { } else {
                XCTFail("expected .decodingFailed, got \(error)")
            }
        } catch {
            XCTFail("unexpected error type: \(error)")
        }
    }
}

private func stubURLSession(
    statusCode: Int,
    body: String,
    headers: [String: String] = ["Content-Type": "application/json"],
    requestInspector: (@Sendable (URLRequest) -> Void)? = nil,
) -> URLSession {
    StubURLProtocol.next = .init(statusCode: statusCode, body: body, headers: headers, inspector: requestInspector)
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [StubURLProtocol.self]
    return URLSession(configuration: configuration)
}

private final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    struct Response: @unchecked Sendable {
        let statusCode: Int
        let body: String
        let headers: [String: String]
        let inspector: (@Sendable (URLRequest) -> Void)?
    }

    nonisolated(unsafe) static var next: Response?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let next = Self.next else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotLoadFromNetwork))
            return
        }
        Self.next = nil
        next.inspector?(request)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: next.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: next.headers,
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(next.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
