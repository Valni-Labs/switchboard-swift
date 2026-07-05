import XCTest
@testable import Switchboard

final class AnthropicMessagesAdapterTests: XCTestCase {

    override func setUp() {
        super.setUp()
        MockAnthropicProtocol.reset()
    }

    private func makeAdapter(
        modelID: String = "fixture-model-large",
        endUserID: String? = "user-1"
    ) -> AnthropicMessagesAdapter {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockAnthropicProtocol.self]
        let session = URLSession(configuration: config)
        return AnthropicMessagesAdapter(
            modelID: modelID,
            apiKey: "swb_test",
            endUserID: endUserID,
            baseURL: URL(string: "https://switchboard.valni.app/v1")!,
            urlSession: session
        )
    }

    func testBuildsAnthropicNativeRequestBody() async throws {
        MockAnthropicProtocol.responseSSE = anthropicSSEFor(text: "hi")
        let provider = makeAdapter()

        var collected = ""
        for try await chunk in provider.generateRaw(messages: [
            ChatMessage(role: .system, text: "You are helpful."),
            ChatMessage(role: .user, text: "hi"),
        ]) {
            if case .text(let t) = chunk { collected += t }
        }

        XCTAssertEqual(collected, "hi")
        guard let recorded = MockAnthropicProtocol.lastRequest,
              let body = recorded.httpBody,
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            return XCTFail("no captured request")
        }

        XCTAssertEqual(recorded.url?.absoluteString, "https://switchboard.valni.app/v1/messages")
        XCTAssertEqual(recorded.value(forHTTPHeaderField: "Authorization"), "Bearer swb_test")
        XCTAssertEqual(recorded.value(forHTTPHeaderField: "anthropic-version"), "2023-06-01")
        XCTAssertEqual(json["model"] as? String, "fixture-model-large")
        XCTAssertEqual(json["stream"] as? Bool, true)
        let system = json["system"] as? [[String: Any]]
        XCTAssertEqual(system?.first?["text"] as? String, "You are helpful.")
        XCTAssertEqual((system?.first?["cache_control"] as? [String: Any])?["type"] as? String, "ephemeral")
        XCTAssertNotNil(json["messages"])
        let metadata = json["metadata"] as? [String: Any]
        XCTAssertEqual(metadata?["user_id"] as? String, "user-1")
        XCTAssertNil(json["tools"], "no tools passed → tools field should be absent")
    }

    func testGenerateRawStreamsTextDeltasFromAnthropicSSE() async throws {
        MockAnthropicProtocol.responseSSE = anthropicSSEFor(text: "hello world")
        let provider = makeAdapter()

        var collected = ""
        for try await chunk in provider.generateRaw(messages: [ChatMessage(role: .user, text: "hi")]) {
            if case .text(let t) = chunk { collected += t }
        }
        XCTAssertEqual(collected, "hello world")
    }

    func testGenerateRawCapturesTokenUsage() async throws {
        MockAnthropicProtocol.responseSSE = anthropicSSEFor(text: "hi", inputTokens: 42, outputTokens: 17)
        let provider = makeAdapter()

        for try await _ in provider.generateRaw(messages: [ChatMessage(role: .user, text: "hi")]) {}
        XCTAssertEqual(provider.lastUsage?.inputTokens, 42)
        XCTAssertEqual(provider.lastUsage?.outputTokens, 17)
    }

    func testGenerateNativeYieldsToolCallsInIndexOrder() async throws {
        MockAnthropicProtocol.responseSSE = anthropicSSEWithTwoToolCalls()
        let provider = makeAdapter()

        let tools = [
            ToolSchema(
                name: "read_file",
                description: "Read a file.",
                parameters: [ToolParameter(name: "path", type: "string", description: "Path", required: true)]
            ),
            ToolSchema(
                name: "write_file",
                description: "Write a file.",
                parameters: [
                    ToolParameter(name: "path", type: "string", description: "Path", required: true),
                    ToolParameter(name: "content", type: "string", description: "Content", required: true),
                ]
            ),
        ]

        var texts: [String] = []
        var calls: [(String, String, String)] = []
        for try await chunk in provider.generateNative(
            messages: [ChatMessage(role: .user, text: "read then write")],
            tools: tools
        ) {
            switch chunk {
            case .text(let t): texts.append(t)
            case .toolCall(let id, let name, let arguments): calls.append((id, name, arguments))
            case .paywall: break
            }
        }

        XCTAssertEqual(calls.count, 2)
        XCTAssertEqual(calls[0].1, "read_file")
        XCTAssertEqual(calls[0].2, "{\"path\":\"a.txt\"}")
        XCTAssertEqual(calls[1].1, "write_file")
        XCTAssertEqual(calls[1].2, "{\"path\":\"a.txt\",\"content\":\"hello\"}")

        guard let recorded = MockAnthropicProtocol.lastRequest,
              let body = recorded.httpBody,
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let wireTools = json["tools"] as? [[String: Any]] else {
            return XCTFail("no captured request or tools")
        }
        XCTAssertEqual(wireTools.count, 2)
        XCTAssertEqual(wireTools[0]["name"] as? String, "read_file")
        let schema = wireTools[0]["input_schema"] as? [String: Any]
        XCTAssertEqual(schema?["type"] as? String, "object")
        XCTAssertEqual((schema?["required"] as? [String])?.sorted(), ["path"])
    }

    func testMapsSwitchboardErrorEnvelopeToProviderError() async throws {
        MockAnthropicProtocol.statusCode = 400
        MockAnthropicProtocol.responseData = try! JSONSerialization.data(withJSONObject: [
            "code": "SWB-2003",
            "error": "Model id has no provider prefix match",
            "model": "not-a-model",
        ])
        let provider = makeAdapter(modelID: "not-a-model")

        do {
            for try await _ in provider.generateRaw(messages: [ChatMessage(role: .user, text: "hi")]) {}
            XCTFail("expected throw")
        } catch let error as ProviderError {
            if case .requestInvalid(let message) = error {
                XCTAssertTrue(message.contains("no provider prefix match"), "unexpected message: \(message)")
            } else {
                XCTFail("expected .requestInvalid for SWB-2003, got: \(error)")
            }
        }
    }

    private func anthropicSSEFor(
        text: String,
        inputTokens: Int = 5,
        outputTokens: Int = 3
    ) -> String {
        let events: [[String: Any]] = [
            ["type": "message_start", "message": ["id": "msg_01Test", "role": "assistant", "usage": ["input_tokens": inputTokens, "output_tokens": 0]]],
            ["type": "content_block_start", "index": 0, "content_block": ["type": "text", "text": ""]],
            ["type": "content_block_delta", "index": 0, "delta": ["type": "text_delta", "text": text]],
            ["type": "content_block_stop", "index": 0],
            ["type": "message_delta", "delta": ["stop_reason": "end_turn"], "usage": ["output_tokens": outputTokens]],
            ["type": "message_stop"],
        ]
        return events.map { "data: \(String(data: try! JSONSerialization.data(withJSONObject: $0), encoding: .utf8)!)\n\n" }.joined()
    }

    private func anthropicSSEWithTwoToolCalls() -> String {
        let events: [[String: Any]] = [
            ["type": "message_start", "message": ["id": "msg_01Tools", "role": "assistant", "usage": ["input_tokens": 10, "output_tokens": 0]]],
            ["type": "content_block_start", "index": 0, "content_block": ["type": "tool_use", "id": "toolu_01A", "name": "read_file", "input": [:]]],
            ["type": "content_block_delta", "index": 0, "delta": ["type": "input_json_delta", "partial_json": "{\"path\":\"a.txt\"}"]],
            ["type": "content_block_stop", "index": 0],
            ["type": "content_block_start", "index": 1, "content_block": ["type": "tool_use", "id": "toolu_02B", "name": "write_file", "input": [:]]],
            ["type": "content_block_delta", "index": 1, "delta": ["type": "input_json_delta", "partial_json": "{\"path\":\"a.txt\",\"content\":\"hello\"}"]],
            ["type": "content_block_stop", "index": 1],
            ["type": "message_delta", "delta": ["stop_reason": "tool_use"], "usage": ["output_tokens": 20]],
            ["type": "message_stop"],
        ]
        return events.map { "data: \(String(data: try! JSONSerialization.data(withJSONObject: $0), encoding: .utf8)!)\n\n" }.joined()
    }
}

final class MockAnthropicProtocol: URLProtocol {
    static var lastRequest: URLRequest?
    static var responseSSE: String?
    static var responseData: Data?
    static var statusCode: Int = 200

    static func reset() {
        lastRequest = nil
        responseSSE = nil
        responseData = nil
        statusCode = 200
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        var recorded = request
        if recorded.httpBody == nil, let stream = recorded.httpBodyStream {
            var body = Data()
            stream.open()
            let bufferSize = 4096
            let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
            defer {
                buffer.deallocate()
                stream.close()
            }
            while stream.hasBytesAvailable {
                let read = stream.read(buffer, maxLength: bufferSize)
                if read <= 0 { break }
                body.append(buffer, count: read)
            }
            recorded.httpBody = body
        }
        MockAnthropicProtocol.lastRequest = recorded

        let contentType = MockAnthropicProtocol.responseSSE != nil ? "text/event-stream" : "application/json"
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: MockAnthropicProtocol.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": contentType]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if let sse = MockAnthropicProtocol.responseSSE {
            client?.urlProtocol(self, didLoad: Data(sse.utf8))
        } else if let data = MockAnthropicProtocol.responseData {
            client?.urlProtocol(self, didLoad: data)
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
