import XCTest
@testable import Switchboard

final class InferenceTests: XCTestCase {

    func testRequestEncodesEnvelopeFieldsWithWireKeys() throws {
        let request = Inference.Request(
            model: "anthropic/claude-sonnet-4-5",
            messages: [.user("hi")],
            maxTokens: 128,
            stream: true,
            user: "end-user-1",
            providerOptions: ["anthropic": ["thinking": .object(["budget_tokens": .number(2048)])]],
            includeNative: true,
        )
        let data = try JSONEncoder().encode(request)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(json["max_tokens"] as? Int, 128)
        XCTAssertEqual(json["include_native"] as? Bool, true)
        let providerOptions = try XCTUnwrap(json["provider_options"] as? [String: Any])
        let anthropic = try XCTUnwrap(providerOptions["anthropic"] as? [String: Any])
        let thinking = try XCTUnwrap(anthropic["thinking"] as? [String: Any])
        XCTAssertEqual(thinking["budget_tokens"] as? Double, 2048)
    }

    func testFrameParsingCoversTheGrammar() throws {
        func frame(_ json: String) throws -> Inference.Frame? {
            try Inference.Frame.parse(Data(json.utf8))
        }

        XCTAssertEqual(try frame(#"{"type":"text_delta","text":"Hel"}"#), .textDelta(text: "Hel"))
        XCTAssertEqual(try frame(#"{"type":"reasoning_delta","text":"hmm"}"#), .reasoningDelta(text: "hmm"))
        XCTAssertEqual(
            try frame(#"{"type":"tool_call","id":"c1","name":"f","arguments_json":"{}"}"#),
            .toolCall(id: "c1", name: "f", argumentsJSON: "{}"),
        )
        XCTAssertEqual(try frame(#"{"type":"usage","input_tokens":9,"output_tokens":4}"#), .usage(inputTokens: 9, outputTokens: 4))
        XCTAssertEqual(try frame(#"{"type":"done","finish_reason":"end_turn"}"#), .done(finishReason: "end_turn"))
        XCTAssertEqual(
            try frame(#"{"type":"native","native":{"kind":1}}"#),
            .native(.object(["kind": .number(1)])),
        )
        XCTAssertEqual(
            try frame(#"{"type":"error","code":"SWB-5205","error":"broken","detail":"boom"}"#),
            .error(code: "SWB-5205", message: "broken", detail: "boom"),
        )
    }

    func testUnknownFrameKindsAreSkipped() throws {
        XCTAssertNil(try Inference.Frame.parse(Data(#"{"type":"hologram_delta","pixels":3}"#.utf8)))
    }

    func testUsageFramesMissingTokenFieldsAreSkippedNotDefaulted() throws {
        XCTAssertNil(try Inference.Frame.parse(Data(#"{"type":"usage","input_tokens":9}"#.utf8)))
        XCTAssertNil(try Inference.Frame.parse(Data(#"{"type":"usage"}"#.utf8)))
    }

    func testResponseDecodesCompletionShapeWithNativeParts() throws {
        let json = #"""
        {
          "id": "msg_1",
          "model": "anthropic/claude-sonnet-4-5",
          "choices": [{
            "index": 0,
            "message": {
              "role": "assistant",
              "content": "Checking.",
              "tool_calls": [{"id": "c1", "type": "function", "function": {"name": "f", "arguments": "{}"}}],
              "native_parts": [{"type": "thinking", "thinking": "hmm", "signature": "sig"}]
            },
            "finish_reason": "tool_use"
          }],
          "usage": {"prompt_tokens": 12, "completion_tokens": 5}
        }
        """#
        let response = try JSONDecoder().decode(Inference.Response.self, from: Data(json.utf8))
        XCTAssertEqual(response.choices.count, 1)
        let message = response.choices[0].message
        XCTAssertEqual(message.content, "Checking.")
        XCTAssertEqual(message.toolCalls?.first?.function.name, "f")
        XCTAssertEqual(message.nativeParts?.count, 1)
        XCTAssertEqual(response.choices[0].finishReason, "tool_use")
        XCTAssertEqual(response.usage, .init(inputTokens: 12, outputTokens: 5))
    }

    func testJSONRoundTrips() throws {
        let original = Inference.JSON.object([
            "text": .string("x"),
            "flag": .bool(true),
            "list": .array([.number(1), .null]),
        ])
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Inference.JSON.self, from: encoded)
        XCTAssertEqual(decoded, original)
    }
}
