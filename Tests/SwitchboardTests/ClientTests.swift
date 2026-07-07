
import XCTest
@testable import Switchboard

final class ClientTests: XCTestCase {

    func testChatCompletionsReturnsParsedResponse() async throws {
        let stub = stubURLSession(
            statusCode: 200,
            body: """
            {
              "id": "chatcmpl_test",
              "model": "fixture-model-large",
              "choices": [{
                "index": 0,
                "message": { "role": "assistant", "content": "hello there" },
                "finish_reason": "stop"
              }],
              "usage": {
                "prompt_tokens": 4,
                "completion_tokens": 2,
                "total_tokens": 6
              }
            }
            """,
        )
        let client = Client(apiKey: "swb_test", urlSession: stub)
        let response = try await client.chatCompletions(
            Chat.Request(model: "fixture-model-large", messages: [.user("hi")]),
        )
        XCTAssertEqual(response.id, "chatcmpl_test")
        XCTAssertEqual(response.content, "hello there")
        XCTAssertEqual(response.usage?.promptTokens, 4)
        XCTAssertEqual(response.usage?.completionTokens, 2)
    }

    func testChatCompletionsThrowsServerErrorWithEnvelope() async {
        let stub = stubURLSession(
            statusCode: 429,
            body: """
            {"code":"SWB-1003","error":"Rate limit exceeded. Try again later."}
            """,
        )
        let client = Client(apiKey: "swb_test", urlSession: stub)
        do {
            _ = try await client.chatCompletions(
                Chat.Request(model: "fixture-model-large", messages: [.user("hi")]),
            )
            XCTFail("expected throw")
        } catch let error as SwitchboardError {
            switch error {
            case .serverError(let status, let code, let message, _):
                XCTAssertEqual(status, 429)
                XCTAssertEqual(code, "SWB-1003")
                XCTAssertEqual(message, "Rate limit exceeded. Try again later.")
            default:
                XCTFail("expected .serverError, got \(error)")
            }
        } catch {
            XCTFail("unexpected error type: \(error)")
        }
    }

    func testChatCompletionsThrowsMissingAPIKey() async {
        let stub = stubURLSession(statusCode: 200, body: "{}")
        let client = Client(apiKey: "", urlSession: stub)
        do {
            _ = try await client.chatCompletions(
                Chat.Request(model: "x", messages: [.user("hi")]),
            )
            XCTFail("expected throw")
        } catch let error as SwitchboardError {
            if case .missingAPIKey = error { } else {
                XCTFail("expected .missingAPIKey, got \(error)")
            }
        } catch {
            XCTFail("unexpected error type: \(error)")
        }
    }

    func testChatCompletionsSendsBearerAuthorizationHeader() async throws {
        var captured: URLRequest?
        let stub = stubURLSession(
            statusCode: 200,
            body: minimalChatResponseBody(),
            requestInspector: { captured = $0 },
        )
        let client = Client(apiKey: "swb_abcdef", urlSession: stub)
        _ = try await client.chatCompletions(
            Chat.Request(model: "x", messages: [.user("hi")]),
        )
        XCTAssertEqual(captured?.value(forHTTPHeaderField: "Authorization"), "Bearer swb_abcdef")
        XCTAssertEqual(captured?.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(captured?.httpMethod, "POST")
    }

    func testChatCompletionsAppendsPathToBaseURL() async throws {
        var captured: URLRequest?
        let stub = stubURLSession(
            statusCode: 200,
            body: minimalChatResponseBody(),
            requestInspector: { captured = $0 },
        )
        let client = Client(
            apiKey: "swb_test",
            baseURL: URL(string: "https://switchboard.example.com")!,
            urlSession: stub,
        )
        _ = try await client.chatCompletions(
            Chat.Request(model: "x", messages: [.user("hi")]),
        )
        XCTAssertEqual(captured?.url?.absoluteString, "https://switchboard.example.com/v1/chat/completions")
    }

    func testStreamChatCompletionsYieldsParsedChunks() async throws {
        let sse = """
        data: {"id":"x","model":"y","choices":[{"index":0,"delta":{"role":"assistant","content":"hi"}}]}

        data: {"id":"x","choices":[{"index":0,"delta":{"content":" there"}}]}

        data: {"id":"x","choices":[],"usage":{"prompt_tokens":2,"completion_tokens":3,"total_tokens":5}}

        data: [DONE]

        """
        let stub = stubURLSession(
            statusCode: 200,
            body: sse,
            headers: ["Content-Type": "text/event-stream"],
        )
        let client = Client(apiKey: "swb_test", urlSession: stub)
        var contents: [String?] = []
        var lastUsage: Chat.Response.Usage?
        for try await chunk in client.streamChatCompletions(
            Chat.Request(model: "y", messages: [.user("hi")]),
        ) {
            contents.append(chunk.choices.first?.delta.content)
            if let usage = chunk.usage { lastUsage = usage }
        }
        XCTAssertEqual(contents, ["hi", " there", nil])
        XCTAssertEqual(lastUsage?.totalTokens, 5)
    }

    func testStreamChatCompletionsForcesStreamFlag() async throws {
        var capturedBody: Data?
        let stub = stubURLSession(
            statusCode: 200,
            body: "data: [DONE]\n\n",
            headers: ["Content-Type": "text/event-stream"],
            requestInspector: { capturedBody = readBody(of: $0) },
        )
        let client = Client(apiKey: "swb_test", urlSession: stub)
        for try await _ in client.streamChatCompletions(
            Chat.Request(model: "y", messages: [.user("hi")], stream: false),
        ) {}
        let body = try XCTUnwrap(capturedBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["stream"] as? Bool, true)
    }

    func testStreamChatCompletionsThrowsServerErrorOnNonOK() async {
        let stub = stubURLSession(
            statusCode: 401,
            body: """
            {"code":"SWB-1001","error":"Authentication required"}
            """,
        )
        let client = Client(apiKey: "swb_test", urlSession: stub)
        do {
            for try await _ in client.streamChatCompletions(
                Chat.Request(model: "x", messages: [.user("hi")]),
            ) {}
            XCTFail("expected throw")
        } catch let error as SwitchboardError {
            switch error {
            case .serverError(let status, let code, _, _):
                XCTAssertEqual(status, 401)
                XCTAssertEqual(code, "SWB-1001")
            default:
                XCTFail("expected .serverError, got \(error)")
            }
        } catch {
            XCTFail("unexpected error type: \(error)")
        }
    }

    func testSupportedProvidersReturnsDecodedIdentifiers() async throws {
        let stub = stubURLSession(
            statusCode: 200,
            body: """
            {"providers":["anthropic","xai","openai"]}
            """,
        )
        let client = Client(apiKey: "swb_test", urlSession: stub)
        let providers = try await client.supportedProviders()
        XCTAssertEqual(
            providers,
            [SupportedProvider("anthropic"), SupportedProvider("xai"), SupportedProvider("openai")],
        )
    }

    func testSupportedProvidersSendsGETWithBearerAuthorizationHeader() async throws {
        var captured: URLRequest?
        let stub = stubURLSession(
            statusCode: 200,
            body: """
            {"providers":[]}
            """,
            requestInspector: { captured = $0 },
        )
        let client = Client(
            apiKey: "swb_abcdef",
            baseURL: URL(string: "https://switchboard.example.com")!,
            urlSession: stub,
        )
        _ = try await client.supportedProviders()
        XCTAssertEqual(captured?.httpMethod, "GET")
        XCTAssertEqual(captured?.value(forHTTPHeaderField: "Authorization"), "Bearer swb_abcdef")
        XCTAssertEqual(captured?.url?.absoluteString, "https://switchboard.example.com/v1/providers")
    }

    func testSupportedProvidersThrowsServerErrorWithEnvelope() async {
        let stub = stubURLSession(
            statusCode: 401,
            body: """
            {"code":"SWB-1001","error":"Authentication required"}
            """,
        )
        let client = Client(apiKey: "swb_test", urlSession: stub)
        do {
            _ = try await client.supportedProviders()
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

    func testSupportedProvidersThrowsMissingAPIKey() async {
        let stub = stubURLSession(statusCode: 200, body: """
        {"providers":[]}
        """)
        let client = Client(apiKey: "", urlSession: stub)
        do {
            _ = try await client.supportedProviders()
            XCTFail("expected throw")
        } catch let error as SwitchboardError {
            if case .missingAPIKey = error { } else {
                XCTFail("expected .missingAPIKey, got \(error)")
            }
        } catch {
            XCTFail("unexpected error type: \(error)")
        }
    }

    func testSupportedProvidersThrowsDecodingFailedOnMalformedBody() async {
        let stub = stubURLSession(
            statusCode: 200,
            body: """
            {"unexpected":"shape"}
            """,
        )
        let client = Client(apiKey: "swb_test", urlSession: stub)
        do {
            _ = try await client.supportedProviders()
            XCTFail("expected throw")
        } catch let error as SwitchboardError {
            if case .decodingFailed = error { } else {
                XCTFail("expected .decodingFailed, got \(error)")
            }
        } catch {
            XCTFail("unexpected error type: \(error)")
        }
    }

    func testStreamChatCompletionsThrowsStreamTruncatedOnMissingDone() async {
        let stub = stubURLSession(
            statusCode: 200,
            body: """
            data: {"id":"x","choices":[{"index":0,"delta":{"content":"hi"}}]}

            """,
            headers: ["Content-Type": "text/event-stream"],
        )
        let client = Client(apiKey: "swb_test", urlSession: stub)
        do {
            for try await _ in client.streamChatCompletions(
                Chat.Request(model: "y", messages: [.user("hi")]),
            ) {}
            XCTFail("expected throw")
        } catch let error as SwitchboardError {
            if case .streamTruncated = error { } else {
                XCTFail("expected .streamTruncated, got \(error)")
            }
        } catch {
            XCTFail("unexpected error type: \(error)")
        }
    }
}

private let bodyDrainBufferSize = 4 * 1024

private func readBody(of request: URLRequest) -> Data? {
    if let body = request.httpBody { return body }
    guard let stream = request.httpBodyStream else { return nil }
    stream.open()
    defer { stream.close() }
    var data = Data()
    let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bodyDrainBufferSize)
    defer { buffer.deallocate() }
    while stream.hasBytesAvailable {
        let read = stream.read(buffer, maxLength: bodyDrainBufferSize)
        if read <= 0 { break }
        data.append(buffer, count: read)
    }
    return data
}

private func minimalChatResponseBody() -> String {
    """
    {"id":"x","model":"y","choices":[{"index":0,"message":{"role":"assistant","content":"ok"},"finish_reason":"stop"}],"usage":{"prompt_tokens":1,"completion_tokens":1,"total_tokens":2}}
    """
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

final class StubURLProtocol: URLProtocol, @unchecked Sendable {
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
