import XCTest
@testable import Switchboard

final class InferenceProviderTests: XCTestCase {

    func testGenerateNativeMapsFramesAndCapturesUsage() async throws {
        let frames = [
            #"{"type":"text_delta","text":"Checking "}"#,
            #"{"type":"reasoning_delta","text":"secret thoughts"}"#,
            #"{"type":"tool_call","id":"c1","name":"get_weather","arguments_json":"{\"city\":\"SF\"}"}"#,
            #"{"type":"usage","input_tokens":9,"output_tokens":4}"#,
            #"{"type":"native","native":{"opaque":true}}"#,
            #"{"type":"done","finish_reason":"tool_use"}"#,
        ].map { "data: \($0)\n" }.joined(separator: "\n")

        let requestPath = LockedBox<String?>(nil)
        let requestBody = LockedBox<Data?>(nil)
        let stub = stubInferenceSession(body: frames) { request in
            requestPath.set(request.url?.path)
            requestBody.set(request.httpBody ?? request.bodyStreamData())
        }

        let provider = InferenceProvider(
            modelID: "anthropic/claude-sonnet-4-5",
            apiKey: "swb_test",
            endUserID: "end-user-1",
            urlSession: stub,
        )

        var received: [NativeStreamChunk] = []
        for try await chunk in provider.generateNative(messages: [ChatMessage(role: .user, text: "hi")], tools: []) {
            received.append(chunk)
        }

        XCTAssertEqual(received.count, 2)
        guard case .text("Checking ") = received[0] else { return XCTFail("expected text chunk, got \(received[0])") }
        guard case .toolCall(let id, let name, let argumentsJSON) = received[1] else { return XCTFail("expected toolCall, got \(received[1])") }
        XCTAssertEqual(id, "c1")
        XCTAssertEqual(name, "get_weather")
        XCTAssertEqual(argumentsJSON, #"{"city":"SF"}"#)
        XCTAssertEqual(provider.lastUsage, GenerationUsage(inputTokens: 9, outputTokens: 4))

        XCTAssertEqual(requestPath.get(), "/v1/switchboard/inference")
        let body = try XCTUnwrap(requestBody.get())
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["user"] as? String, "end-user-1")
        XCTAssertEqual(json["stream"] as? Bool, true)
        XCTAssertNotNil(json["max_tokens"])
        XCTAssertNil(json["tools"])
    }

    func testGenerateRawYieldsTextOnly() async throws {
        let frames = [
            #"{"type":"text_delta","text":"Hello"}"#,
            #"{"type":"tool_call","id":"c1","name":"f","arguments_json":"{}"}"#,
            #"{"type":"done","finish_reason":"stop"}"#,
        ].map { "data: \($0)\n" }.joined(separator: "\n")
        let stub = stubInferenceSession(body: frames, inspector: nil)

        let provider = InferenceProvider(modelID: "openai/gpt-5", apiKey: "swb_test", urlSession: stub)
        var received: [RawStreamChunk] = []
        for try await chunk in provider.generateRaw(messages: [ChatMessage(role: .user, text: "hi")]) {
            received.append(chunk)
        }
        XCTAssertEqual(received, [.text("Hello")])
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
