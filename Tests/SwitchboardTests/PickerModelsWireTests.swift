
import XCTest
@testable import Switchboard

final class PickerModelsWireTests: XCTestCase {

    func testModelsReturnsDecodedPickerModels() async throws {
        let stub = stubURLSession(
            statusCode: 200,
            body: """
            {
              "models": [
                {
                  "id": "test-model-large",
                  "display_name": "Test Model Large",
                  "context_window": 200000,
                  "max_output_tokens": 8192,
                  "input_formats": ["text", "image"],
                  "capabilities": ["tool_calling"]
                },
                {
                  "id": "test-model-small",
                  "display_name": "Test Model Small",
                  "context_window": 32000,
                  "max_output_tokens": null,
                  "input_formats": ["text"],
                  "capabilities": []
                }
              ]
            }
            """,
        )
        let client = Client(apiKey: "swb_test", urlSession: stub)
        let models = try await client.models()
        XCTAssertEqual(models.count, 2)
        let large = try XCTUnwrap(models.first)
        XCTAssertEqual(large.id, "test-model-large")
        XCTAssertEqual(large.displayName, "Test Model Large")
        XCTAssertEqual(large.contextWindow, 200000)
        XCTAssertEqual(large.maxOutputTokens, 8192)
        XCTAssertEqual(large.inputFormats, ["text", "image"])
        XCTAssertEqual(large.capabilities, ["tool_calling"])
        let small = try XCTUnwrap(models.last)
        XCTAssertEqual(small.id, "test-model-small")
        XCTAssertNil(small.maxOutputTokens)
        XCTAssertEqual(small.inputFormats, ["text"])
        XCTAssertEqual(small.capabilities, [])
    }

    func testModelsSendsGETWithBearerAuthorizationHeader() async throws {
        var captured: URLRequest?
        let stub = stubURLSession(
            statusCode: 200,
            body: """
            {"models":[]}
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
        {"models":[]}
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
            {"models":[{"id":"test-model-large"}]}
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
