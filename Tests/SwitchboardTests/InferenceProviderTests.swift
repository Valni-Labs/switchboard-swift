import XCTest
import SwitchboardNative
@testable import Switchboard

final class InferenceProviderTests: XCTestCase {

    func testAnthropicBodyStreamsChunksAndSendsRequiredEnvelope() async throws {
        let events = [
            #"{"type":"message_start","message":{"id":"msg_1","role":"assistant","model":"claude-sonnet-5","usage":{"input_tokens":9,"output_tokens":0,"cache_creation_input_tokens":3,"cache_read_input_tokens":6}}}"#,
            #"{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Checking "}}"#,
            #"{"type":"content_block_delta","index":0,"delta":{"type":"thinking_delta","thinking":"quiet plan"}}"#,
            #"{"type":"content_block_start","index":1,"content_block":{"type":"tool_use","id":"c1","name":"get_weather","input":{}}}"#,
            #"{"type":"content_block_delta","index":1,"delta":{"type":"input_json_delta","partial_json":"{\"city\":\"SF\"}"}}"#,
            #"{"type":"content_block_stop","index":1}"#,
            #"{"type":"message_delta","delta":{"stop_reason":"tool_use"},"usage":{"output_tokens":4}}"#,
            #"{"type":"message_stop"}"#,
        ].map { "data: \($0)\n" }.joined(separator: "\n")

        let requestPath = LockedBox<String?>(nil)
        let requestBody = LockedBox<Data?>(nil)
        let stub = stubInferenceSession(body: events) { request in
            requestPath.set(request.url?.path)
            requestBody.set(request.httpBody ?? request.bodyStreamData())
        }

        let provider = try InferenceProvider(
            apiKey: "swb_test",
            endUserID: "end-user-1",
            urlSession: stub,
        )

        let native = AnthropicMessagesRequest(
            model: "claude-sonnet-5",
            messages: [AnthropicMessage(role: .user, content: .string("hi"))],
            maxTokens: 64,
            thinking: .adaptive(AnthropicThinkingAdaptive(type: "adaptive", display: .summarized)),
            outputConfig: AnthropicOutputConfig(effort: .high),
        )

        var received: [GenerationChunk] = []
        for try await chunk in provider.generate(.anthropic(native)) {
            received.append(chunk)
        }

        XCTAssertEqual(received.count, 3)
        guard case .text("Checking ") = received[0] else { return XCTFail("expected text chunk, got \(received[0])") }
        guard case .reasoning("quiet plan") = received[1] else { return XCTFail("expected reasoning chunk, got \(received[1])") }
        guard case .toolCall(let id, let name, let argumentsJSON) = received[2] else { return XCTFail("expected toolCall, got \(received[2])") }
        XCTAssertEqual(id, "c1")
        XCTAssertEqual(name, "get_weather")
        XCTAssertEqual(argumentsJSON, #"{"city":"SF"}"#)
        XCTAssertEqual(provider.lastUsage, GenerationUsage(inputTokens: 9, outputTokens: 4, cacheCreationTokens: 3, cacheReadTokens: 6))

        XCTAssertEqual(requestPath.get(), "/v1/switchboard/inference")
        let body = try XCTUnwrap(requestBody.get())
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["user_id"] as? String, "end-user-1")
        XCTAssertFalse(try XCTUnwrap(json["idempotency_key"] as? String).isEmpty)
        XCTAssertFalse(try XCTUnwrap(json["time"] as? String).isEmpty)
        let kind = try XCTUnwrap(json["kind"] as? [String: Any])
        let anthropicBody = try XCTUnwrap(kind["anthropic"] as? [String: Any])
        XCTAssertEqual(anthropicBody["model"] as? String, "claude-sonnet-5")
        XCTAssertEqual(anthropicBody["stream"] as? Bool, true)
        XCTAssertEqual(anthropicBody["max_tokens"] as? Int, 64)
        let outputConfig = try XCTUnwrap(anthropicBody["output_config"] as? [String: Any])
        XCTAssertEqual(outputConfig["effort"] as? String, "high")
        XCTAssertNil(json["user"])
    }

    func testOpenAIGenericBodyStreamsTextAndUsage() async throws {
        let events = [
            #"{"id":"c","object":"chat.completion.chunk","model":"gpt-5","choices":[{"index":0,"delta":{"content":"Hello"},"finish_reason":null}]}"#,
            #"{"id":"c","object":"chat.completion.chunk","model":"gpt-5","choices":[],"usage":{"prompt_tokens":7,"completion_tokens":3,"total_tokens":10,"prompt_tokens_details":{"cached_tokens":5,"cache_write_tokens":2}}}"#,
            "[DONE]",
        ].map { "data: \($0)\n" }.joined(separator: "\n")
        let stub = stubInferenceSession(body: events, inspector: nil)

        let provider = try InferenceProvider(apiKey: "swb_test", endUserID: "end-user-1", urlSession: stub)
        let native = OpenAIChatRequest(
            model: "gpt-5",
            messages: [OpenAIChatMessage(role: .user, content: .string("hi"))],
        )

        var received: [GenerationChunk] = []
        for try await chunk in provider.generate(.openaiGeneric(native)) {
            received.append(chunk)
        }
        XCTAssertEqual(received.count, 1)
        guard case .text("Hello") = received[0] else { return XCTFail("expected text chunk, got \(received[0])") }
        XCTAssertEqual(provider.lastUsage, GenerationUsage(inputTokens: 7, outputTokens: 3, cacheCreationTokens: 2, cacheReadTokens: 5))
    }

    func testOpenAIResponsesBodyCapturesCachedInputTokens() async throws {
        let events = [
            #"{"type":"response.output_text.delta","delta":"Hi"}"#,
            #"{"type":"response.completed","response":{"status":"completed","usage":{"input_tokens":11,"output_tokens":2,"total_tokens":13,"input_tokens_details":{"cached_tokens":8,"cache_write_tokens":1}}}}"#,
        ].map { "data: \($0)\n" }.joined(separator: "\n")
        let stub = stubInferenceSession(body: events, inspector: nil)

        let provider = try InferenceProvider(apiKey: "swb_test", endUserID: "end-user-1", urlSession: stub)
        let native = OpenAIResponsesRequest(
            model: "gpt-5-pro",
            input: .string("hi"),
        )

        var received: [GenerationChunk] = []
        for try await chunk in provider.generate(.openaiPro(native)) {
            received.append(chunk)
        }
        XCTAssertEqual(received.count, 1)
        XCTAssertEqual(provider.lastUsage, GenerationUsage(inputTokens: 11, outputTokens: 2, cacheCreationTokens: 1, cacheReadTokens: 8))
    }

    func testUsageWithoutCacheFieldsDefaultsCacheTokensToZero() async throws {
        let events = [
            #"{"type":"message_start","message":{"id":"msg_1","role":"assistant","model":"claude-sonnet-5","usage":{"input_tokens":5,"output_tokens":0}}}"#,
            #"{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"hi"}}"#,
            #"{"type":"message_delta","delta":{"stop_reason":"end_turn"},"usage":{"output_tokens":1}}"#,
            #"{"type":"message_stop"}"#,
        ].map { "data: \($0)\n" }.joined(separator: "\n")
        let stub = stubInferenceSession(body: events, inspector: nil)

        let provider = try InferenceProvider(apiKey: "swb_test", endUserID: "end-user-1", urlSession: stub)
        let native = AnthropicMessagesRequest(
            model: "claude-sonnet-5",
            messages: [AnthropicMessage(role: .user, content: .string("hi"))],
            maxTokens: 8,
        )

        for try await _ in provider.generate(.anthropic(native)) {}
        XCTAssertEqual(provider.lastUsage, GenerationUsage(inputTokens: 5, outputTokens: 1, cacheCreationTokens: 0, cacheReadTokens: 0))
    }

    func testOpenAIProStreamSkipsUnknownEventsAndYieldsKnownChunks() async throws {
        let events = [
            #"{"type":"response.created","response":{"id":"resp_1"}}"#,
            #"{"type":"response.in_progress","sequence_number":1,"response":{"id":"resp_1"}}"#,
            #"{"type":"response.output_item.added","output_index":0,"sequence_number":2,"item":{"type":"reasoning","id":"rs_1","summary":[]}}"#,
            #"{"type":"response.reasoning_summary_part.added","item_id":"rs_1","output_index":0,"summary_index":0,"sequence_number":3,"part":{"type":"summary_text","text":""}}"#,
            #"{"type":"response.reasoning_summary_text.delta","item_id":"rs_1","output_index":0,"summary_index":0,"sequence_number":4,"delta":"weighing options"}"#,
            #"{"type":"response.content_part.added","item_id":"msg_1","output_index":1,"content_index":0,"sequence_number":5,"part":{"type":"output_text","text":""}}"#,
            #"{"type":"response.output_text.delta","delta":"Hello"}"#,
            #"{"type":"response.output_text.done","item_id":"msg_1","output_index":1,"content_index":0,"sequence_number":6,"text":"Hello"}"#,
            #"{"type":"response.web_search_call.searching","sequence_number":7,"output_index":2,"item_id":"ws_1"}"#,
            #"{"type":"response.output_item.done","item":{"type":"web_search_call","id":"ws_1","status":"completed"}}"#,
            #"{"type":"response.function_call_arguments.delta","item_id":"fc_1","output_index":3,"sequence_number":8,"delta":"{\"city\":"}"#,
            #"{"type":"response.function_call_arguments.done","item_id":"fc_1","output_index":3,"sequence_number":9,"name":"get_weather","arguments":"{\"city\":\"SF\"}"}"#,
            #"{"type":"response.output_item.done","item":{"type":"function_call","id":"fc_1","call_id":"call_1","name":"get_weather","arguments":"{\"city\":\"SF\"}"}}"#,
            #"{"type":"response.completed","response":{"status":"completed","usage":{"input_tokens":11,"output_tokens":5,"total_tokens":16}}}"#,
        ].map { "data: \($0)\n" }.joined(separator: "\n")
        let stub = stubInferenceSession(body: events, inspector: nil)

        let provider = try InferenceProvider(apiKey: "swb_test", endUserID: "end-user-1", urlSession: stub)
        let native = OpenAIResponsesRequest(model: "gpt-5.2-pro", input: .string("hi"))

        var received: [GenerationChunk] = []
        for try await chunk in provider.generate(.openaiPro(native)) {
            received.append(chunk)
        }

        XCTAssertEqual(received.count, 3)
        guard case .reasoning("weighing options") = received[0] else { return XCTFail("expected reasoning chunk, got \(received[0])") }
        guard case .text("Hello") = received[1] else { return XCTFail("expected text chunk, got \(received[1])") }
        guard case .toolCall(let id, let name, let argumentsJSON) = received[2] else { return XCTFail("expected toolCall, got \(received[2])") }
        XCTAssertEqual(id, "call_1")
        XCTAssertEqual(name, "get_weather")
        XCTAssertEqual(argumentsJSON, #"{"city":"SF"}"#)
        XCTAssertEqual(provider.lastUsage, GenerationUsage(inputTokens: 11, outputTokens: 5))
    }

    func testOpenAIProIncompleteStreamCompletesWithUsage() async throws {
        let events = [
            #"{"type":"response.created","response":{"id":"resp_1"}}"#,
            #"{"type":"response.output_text.delta","delta":"partial"}"#,
            #"{"type":"response.incomplete","sequence_number":2,"response":{"status":"incomplete","usage":{"input_tokens":9,"output_tokens":2,"total_tokens":11}}}"#,
        ].map { "data: \($0)\n" }.joined(separator: "\n")
        let stub = stubInferenceSession(body: events, inspector: nil)

        let provider = try InferenceProvider(apiKey: "swb_test", endUserID: "end-user-1", urlSession: stub)
        let native = OpenAIResponsesRequest(model: "gpt-5.2-pro", input: .string("hi"))

        var received: [GenerationChunk] = []
        for try await chunk in provider.generate(.openaiPro(native)) {
            received.append(chunk)
        }

        XCTAssertEqual(received.count, 1)
        guard case .text("partial") = received[0] else { return XCTFail("expected text chunk, got \(received[0])") }
        XCTAssertEqual(provider.lastUsage, GenerationUsage(inputTokens: 9, outputTokens: 2))
    }

    func testTruncatedAnthropicStreamThrows() async throws {
        let events = [
            #"{"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"partial"}}"#,
        ].map { "data: \($0)\n" }.joined(separator: "\n")
        let stub = stubInferenceSession(body: events, inspector: nil)

        let provider = try InferenceProvider(apiKey: "swb_test", endUserID: "end-user-1", urlSession: stub)
        let native = AnthropicMessagesRequest(
            model: "claude-sonnet-5",
            messages: [AnthropicMessage(role: .user, content: .string("hi"))],
            maxTokens: 8,
        )

        do {
            for try await _ in provider.generate(.anthropic(native)) {}
            XCTFail("expected a truncation error")
        } catch {
            XCTAssertTrue(error is ProviderError)
        }
    }

    func testEmptyEndUserIDIsUnconstructable() {
        XCTAssertThrowsError(try InferenceProvider(apiKey: "swb_test", endUserID: "")) { error in
            guard case ProviderError.missingEndUserID = error else {
                return XCTFail("expected missingEndUserID, got \(error)")
            }
        }
    }
}

private final class LockedBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) {
        self.value = value
    }

    func set(_ newValue: Value) {
        lock.lock(); defer { lock.unlock() }
        value = newValue
    }

    func get() -> Value {
        lock.lock(); defer { lock.unlock() }
        return value
    }
}

private extension URLRequest {
    func bodyStreamData() -> Data? {
        guard let stream = httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        let bufferSize = 4096
        let buffer = UnsafeMutablePointer<UInt8>.allocate(capacity: bufferSize)
        defer { buffer.deallocate() }
        while stream.hasBytesAvailable {
            let read = stream.read(buffer, maxLength: bufferSize)
            if read <= 0 { break }
            data.append(buffer, count: read)
        }
        return data
    }
}

private func stubInferenceSession(
    body: String,
    inspector: (@Sendable (URLRequest) -> Void)?,
) -> URLSession {
    InferenceStubURLProtocol.next.set(.init(body: body, inspector: inspector))
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [InferenceStubURLProtocol.self]
    return URLSession(configuration: configuration)
}

private final class InferenceStubURLProtocol: URLProtocol, @unchecked Sendable {
    struct Response: @unchecked Sendable {
        let body: String
        let inspector: (@Sendable (URLRequest) -> Void)?
    }

    static let next = LockedBox<Response?>(nil)

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let next = Self.next.get() else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotLoadFromNetwork))
            return
        }
        Self.next.set(nil)
        next.inspector?(request)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "text/event-stream"],
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(next.body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
