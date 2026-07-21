import XCTest
@testable import Switchboard

final class UsageWireTests: XCTestCase {

    private static let pageBody = """
    {
      "company_id": "co_test",
      "records": [
        {
          "id": 42,
          "at": 1789000000,
          "end_user_id": "u_eval",
          "model_id": "kimi-k2.7-code",
          "provider_id": "moonshot",
          "prompt_tokens": 27,
          "completion_tokens": 468,
          "cache_creation_tokens": 0,
          "cache_read_tokens": 27,
          "reasoning_tokens": 411,
          "cost_micro_cents": 1898
        }
      ],
      "next_before_at": 1789000000,
      "next_before_id": 42
    }
    """

    func testUsageReturnsDecodedPage() async throws {
        let stub = stubbedURLSession(statusCode: 200, body: Self.pageBody)
        let client = Client(apiKey: "swb_test", urlSession: stub)
        let page = try await client.usage()
        XCTAssertEqual(page.companyId, "co_test")
        XCTAssertEqual(page.nextBeforeAt, 1789000000)
        XCTAssertEqual(page.nextBeforeId, 42)
        let record = try XCTUnwrap(page.records.first)
        XCTAssertEqual(record.id, 42)
        XCTAssertEqual(record.endUserId, "u_eval")
        XCTAssertEqual(record.modelId, "kimi-k2.7-code")
        XCTAssertEqual(record.providerId, "moonshot")
        XCTAssertEqual(record.promptTokens, 27)
        XCTAssertEqual(record.completionTokens, 468)
        XCTAssertEqual(record.cacheReadTokens, 27)
        XCTAssertEqual(record.reasoningTokens, 411)
        XCTAssertEqual(record.costMicroCents, 1898)
    }

    func testUsageSendsFiltersAsQueryItems() async throws {
        let capturedURL = CapturedValue<URL>()
        let stub = stubbedURLSession(statusCode: 200, body: Self.pageBody) { request in
            capturedURL.set(request.url)
        }
        let client = Client(apiKey: "swb_test", urlSession: stub)
        _ = try await client.usage(endUserID: "u_eval", since: 100, until: 200, limit: 25, beforeAt: 300, beforeID: 7)
        let url = try XCTUnwrap(capturedURL.get())
        XCTAssertEqual(url.path, "/v1/switchboard/usage")
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let items = try XCTUnwrap(components.queryItems)
        XCTAssertEqual(items, [
            URLQueryItem(name: "user_id", value: "u_eval"),
            URLQueryItem(name: "since", value: "100"),
            URLQueryItem(name: "until", value: "200"),
            URLQueryItem(name: "limit", value: "25"),
            URLQueryItem(name: "before_at", value: "300"),
            URLQueryItem(name: "before_id", value: "7"),
        ])
    }

    func testUsageOmitsQueryWhenNoFilters() async throws {
        let capturedURL = CapturedValue<URL>()
        let stub = stubbedURLSession(statusCode: 200, body: Self.pageBody) { request in
            capturedURL.set(request.url)
        }
        let client = Client(apiKey: "swb_test", urlSession: stub)
        _ = try await client.usage()
        let url = try XCTUnwrap(capturedURL.get())
        XCTAssertNil(url.query)
    }

    func testUsageServerErrorSurfacesAsServerError() async throws {
        let stub = stubbedURLSession(statusCode: 401, body: """
        {"code": "SWB-1001", "error": "Authentication required"}
        """)
        let client = Client(apiKey: "swb_test", urlSession: stub)
        do {
            _ = try await client.usage()
            XCTFail("expected serverError")
        } catch let SwitchboardError.serverError(status, code, _, _) {
            XCTAssertEqual(status, 401)
            XCTAssertEqual(code, "SWB-1001")
        }
    }
}

private final class CapturedValue<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value?

    func set(_ newValue: Value?) {
        lock.lock()
        value = newValue
        lock.unlock()
    }

    func get() -> Value? {
        lock.lock()
        defer { lock.unlock() }
        return value
    }
}

private func stubbedURLSession(
    statusCode: Int,
    body: String,
    headers: [String: String] = ["Content-Type": "application/json"],
    requestInspector: (@Sendable (URLRequest) -> Void)? = nil,
) -> URLSession {
    UsageStubURLProtocol.next = .init(statusCode: statusCode, body: body, headers: headers, inspector: requestInspector)
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [UsageStubURLProtocol.self]
    return URLSession(configuration: configuration)
}

private final class UsageStubURLProtocol: URLProtocol, @unchecked Sendable {
    struct StubResponse: @unchecked Sendable {
        let statusCode: Int
        let body: String
        let headers: [String: String]
        let inspector: (@Sendable (URLRequest) -> Void)?
    }

    nonisolated(unsafe) static var next: StubResponse?

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
