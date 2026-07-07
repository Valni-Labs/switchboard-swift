import XCTest
@testable import Switchboard

final class OpenAIResponsesAdapterTests: XCTestCase {

    override func setUp() {
        super.setUp()
        MockResponsesProtocol.reset()
    }

    private func makeAdapter(
        modelID: String = "gpt-5.5-pro",
        endUserID: String? = "user-1",
        reasoningEffort: ReasoningEffort? = nil
    ) -> OpenAIResponsesAdapter {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockResponsesProtocol.self]
        let session = URLSession(configuration: config)
        return OpenAIResponsesAdapter(
            modelID: modelID,
            apiKey: "swb_test",
            endUserID: endUserID,
            reasoningEffort: reasoningEffort,
            baseURL: URL(string: "https://switchboard.valni.app/v1")!,
            urlSession: session
        )
    }

    func testBuildsResponsesRequestBody() async throws {
        MockResponsesProtocol.responseSSE = responsesSSEFor(text: "hi")
        let provider = makeAdapter(reasoningEffort: .high)

        var collected = ""
        for try await chunk in provider.generateRaw(messages: [
            ChatMessage(role: .system, text: "You are helpful."),
            ChatMessage(role: .user, text: "hi"),
        ]) {
            if case .text(let t) = chunk { collected += t }
        }

        XCTAssertEqual(collected, "hi")
        guard let recorded = MockResponsesProtocol.lastRequest,
              let body = recorded.httpBody,
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            return XCTFail("no captured request")
        }

        XCTAssertEqual(recorded.url?.absoluteString, "https://switchboard.valni.app/v1/responses")
        XCTAssertEqual(recorded.value(forHTTPHeaderField: "Authorization"), "Bearer swb_test")
        XCTAssertEqual(json["model"] as? String, "gpt-5.5-pro")
        XCTAssertEqual(json["stream"] as? Bool, true)
        XCTAssertEqual(json["user"] as? String, "user-1")
        XCTAssertEqual((json["reasoning"] as? [String: Any])?["effort"] as? String, "high")
        XCTAssertNil(json["tools"], "no tools passed → tools field should be absent")

        let input = json["input"] as? [[String: Any]]
        XCTAssertEqual(input?.count, 2)
        XCTAssertEqual(input?[0]["role"] as? String, "system")
        let systemContent = input?[0]["content"] as? [[String: Any]]
        XCTAssertEqual(systemContent?.first?["type"] as? String, "input_text")
        XCTAssertEqual(systemContent?.first?["text"] as? String, "You are helpful.")
        XCTAssertEqual(input?[1]["role"] as? String, "user")
    }

    func testOmitsReasoningWhenEffortNil() async throws {
        MockResponsesProtocol.responseSSE = responsesSSEFor(text: "hi")
        let provider = makeAdapter(reasoningEffort: nil)
        for try await _ in provider.generateRaw(messages: [ChatMessage(role: .user, text: "hi")]) {}

        guard let body = MockResponsesProtocol.lastRequest?.httpBody,
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
            return XCTFail("no captured request")
        }
        XCTAssertNil(json["reasoning"], "reasoning must be absent when no effort is set")
    }

    func testGenerateRawStreamsTextDeltas() async throws {
        MockResponsesProtocol.responseSSE = responsesSSEFor(text: "hello world")
        let provider = makeAdapter()

        var collected = ""
        for try await chunk in provider.generateRaw(messages: [ChatMessage(role: .user, text: "hi")]) {
            if case .text(let t) = chunk { collected += t }
        }
        XCTAssertEqual(collected, "hello world")
    }

    func testStopsReadingAtDoneTerminator() async throws {
        MockResponsesProtocol.responseSSE = responsesSSEFor(text: "before")
            + "data: [DONE]\n\n"
            + "data: {\"type\": \"response.output_text.delta\", \"delta\": \"after\"}\n\n"
        let provider = makeAdapter()

        var collected = ""
        for try await chunk in provider.generateRaw(messages: [ChatMessage(role: .user, text: "hi")]) {
            if case .text(let t) = chunk { collected += t }
        }
        XCTAssertEqual(collected, "before")
    }

    func testCapturesTokenUsageFromResponseCompleted() async throws {
        MockResponsesProtocol.responseSSE = responsesSSEFor(text: "hi", inputTokens: 42, outputTokens: 17)
        let provider = makeAdapter()

        for try await _ in provider.generateRaw(messages: [ChatMessage(role: .user, text: "hi")]) {}
        XCTAssertEqual(provider.lastUsage?.inputTokens, 42)
        XCTAssertEqual(provider.lastUsage?.outputTokens, 17)
    }

    func testGenerateNativeYieldsToolCallsInOrder() async throws {
        MockResponsesProtocol.responseSSE = responsesSSEWithTwoToolCalls()
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

        var calls: [(String, String, String)] = []
        for try await chunk in provider.generateNative(
            messages: [ChatMessage(role: .user, text: "read then write")],
            tools: tools
        ) {
            if case .toolCall(let id, let name, let arguments) = chunk { calls.append((id, name, arguments)) }
        }

        XCTAssertEqual(calls.count, 2)
        XCTAssertEqual(calls[0].0, "call_A")
        XCTAssertEqual(calls[0].1, "read_file")
        XCTAssertEqual(calls[0].2, "{\"path\":\"a.txt\"}")
        XCTAssertEqual(calls[1].0, "call_B")
        XCTAssertEqual(calls[1].1, "write_file")
        XCTAssertEqual(calls[1].2, "{\"path\":\"a.txt\",\"content\":\"hello\"}")

        guard let body = MockResponsesProtocol.lastRequest?.httpBody,
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let wireTools = json["tools"] as? [[String: Any]] else {
            return XCTFail("no captured request or tools")
        }
        XCTAssertEqual(wireTools.count, 2)
        XCTAssertEqual(wireTools[0]["type"] as? String, "function")
        XCTAssertEqual(wireTools[0]["name"] as? String, "read_file")
        let schema = wireTools[0]["parameters"] as? [String: Any]
        XCTAssertEqual(schema?["type"] as? String, "object")
        XCTAssertEqual((schema?["required"] as? [String])?.sorted(), ["path"])
    }

    func testEncodesToolHistoryAsFunctionCallAndOutput() async throws {
        MockResponsesProtocol.responseSSE = responsesSSEFor(text: "done")
        let provider = makeAdapter()

        let assistant = ChatMessage(
            role: .assistant,
            content: .text(""),
            toolCalls: [Chat.ToolCall(id: "call_A", function: .init(name: "read_file", arguments: "{\"path\":\"a.txt\"}"))]
        )
        let toolResult = ChatMessage.tool(callID: "call_A", result: "file contents")

        for try await _ in provider.generateNative(
            messages: [ChatMessage(role: .user, text: "read a.txt"), assistant, toolResult],
            tools: []
        ) {}

        guard let body = MockResponsesProtocol.lastRequest?.httpBody,
              let json = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let input = json["input"] as? [[String: Any]] else {
            return XCTFail("no captured request")
        }
        XCTAssertTrue(input.contains { $0["type"] as? String == "function_call" && $0["call_id"] as? String == "call_A" })
        let output = input.first { $0["type"] as? String == "function_call_output" }
        XCTAssertEqual(output?["call_id"] as? String, "call_A")
        XCTAssertEqual(output?["output"] as? String, "file contents")
    }

    func testMapsSwitchboardErrorEnvelopeToProviderError() async throws {
        MockResponsesProtocol.statusCode = 400
        MockResponsesProtocol.responseData = try! JSONSerialization.data(withJSONObject: [
            "code": "SWB-2003",
            "error": "Model is not supported on this endpoint",
            "model": "gpt-5.5-pro",
        ])
        let provider = makeAdapter()

        do {
            for try await _ in provider.generateRaw(messages: [ChatMessage(role: .user, text: "hi")]) {}
            XCTFail("expected throw")
        } catch let error as ProviderError {
            if case .requestInvalid(let message) = error {
                XCTAssertTrue(message.contains("not supported"), "unexpected message: \(message)")
            } else {
                XCTFail("expected .requestInvalid for SWB-2003, got: \(error)")
            }
        }
    }

    private func responsesSSEFor(
        text: String,
        inputTokens: Int = 5,
        outputTokens: Int = 3
    ) -> String {
        let events: [[String: Any]] = [
            ["type": "response.output_text.delta", "delta": text],
            ["type": "response.completed", "response": ["usage": ["input_tokens": inputTokens, "output_tokens": outputTokens]]],
        ]
        return events.map { "data: \(String(data: try! JSONSerialization.data(withJSONObject: $0), encoding: .utf8)!)\n\n" }.joined()
    }

    private func responsesSSEWithTwoToolCalls() -> String {
        let events: [[String: Any]] = [
            ["type": "response.output_item.added", "item": ["type": "function_call", "id": "fc_1", "call_id": "call_A", "name": "read_file", "arguments": ""]],
            ["type": "response.function_call_arguments.delta", "item_id": "fc_1", "delta": "{\"path\":\"a.txt\"}"],
            ["type": "response.output_item.added", "item": ["type": "function_call", "id": "fc_2", "call_id": "call_B", "name": "write_file", "arguments": ""]],
            ["type": "response.function_call_arguments.delta", "item_id": "fc_2", "delta": "{\"path\":\"a.txt\",\"content\":\"hello\"}"],
            ["type": "response.completed", "response": ["usage": ["input_tokens": 10, "output_tokens": 20]]],
        ]
        return events.map { "data: \(String(data: try! JSONSerialization.data(withJSONObject: $0), encoding: .utf8)!)\n\n" }.joined()
    }
}

final class MockResponsesProtocol: URLProtocol {
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
        MockResponsesProtocol.lastRequest = recorded

        let contentType = MockResponsesProtocol.responseSSE != nil ? "text/event-stream" : "application/json"
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: MockResponsesProtocol.statusCode,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": contentType]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if let sse = MockResponsesProtocol.responseSSE {
            client?.urlProtocol(self, didLoad: Data(sse.utf8))
        } else if let data = MockResponsesProtocol.responseData {
            client?.urlProtocol(self, didLoad: data)
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
