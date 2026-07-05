
import XCTest
@testable import Switchboard

final class SwitchboardChatCompletionsTests: XCTestCase {

    func testAssistantMessageDecodesToolCallsAndCoalescesNullContent() throws {
        let json = """
        {
          "role": "assistant",
          "content": null,
          "tool_calls": [
            {
              "id": "call_abc",
              "type": "function",
              "function": { "name": "get_weather", "arguments": "{\\"location\\":\\"SF\\"}" }
            }
          ]
        }
        """.data(using: .utf8)!

        let message = try JSONDecoder().decode(Chat.Message.self, from: json)

        XCTAssertEqual(message.role, .assistant)
        XCTAssertEqual(message.content, .text(""))
        XCTAssertNil(message.toolCallId)
        let calls = try XCTUnwrap(message.toolCalls)
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls[0].id, "call_abc")
        XCTAssertEqual(calls[0].type, "function")
        XCTAssertEqual(calls[0].function.name, "get_weather")
        XCTAssertEqual(calls[0].function.arguments, #"{"location":"SF"}"#)
    }

    func testToolMessageDecodesToolCallId() throws {
        let json = """
        {
          "role": "tool",
          "content": "42",
          "tool_call_id": "call_abc"
        }
        """.data(using: .utf8)!

        let message = try JSONDecoder().decode(Chat.Message.self, from: json)

        XCTAssertEqual(message.role, .tool)
        XCTAssertEqual(message.content, .text("42"))
        XCTAssertEqual(message.toolCallId, "call_abc")
        XCTAssertNil(message.toolCalls)
    }

    func testNonAssistantWithoutContentFailsDecode() {
        for role in ["user", "system", "tool"] {
            let json = """
            { "role": "\(role)", "content": null }
            """.data(using: .utf8)!
            XCTAssertThrowsError(try JSONDecoder().decode(Chat.Message.self, from: json),
                                 "role: \(role) with null content should throw") { error in
                guard case DecodingError.dataCorrupted = error else {
                    return XCTFail("\(role): expected DecodingError.dataCorrupted, got \(error)")
                }
            }
        }
    }

    func testAssistantWithToolCallsEncodesWithoutSpuriousNulls() throws {
        let message = Chat.Message(
            role: .assistant,
            content: .text(""),
            toolCalls: [
                Chat.ToolCall(id: "call_abc", function: .init(name: "get_weather", arguments: #"{"location":"SF"}"#)),
            ],
        )

        let data = try JSONEncoder().encode(message)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(object["role"] as? String, "assistant")
        XCTAssertEqual(object["content"] as? String, "")
        XCTAssertNil(object["tool_call_id"], "should be absent, not null")
        let calls = try XCTUnwrap(object["tool_calls"] as? [[String: Any]])
        XCTAssertEqual(calls.count, 1)
        XCTAssertEqual(calls[0]["id"] as? String, "call_abc")
        let function = try XCTUnwrap(calls[0]["function"] as? [String: Any])
        XCTAssertEqual(function["name"] as? String, "get_weather")
        XCTAssertEqual(function["arguments"] as? String, #"{"location":"SF"}"#)
    }

    func testToolMessageEncodesToolCallIdAndOmitsToolCalls() throws {
        let message = Chat.Message.tool(callId: "call_abc", result: "42")
        let data = try JSONEncoder().encode(message)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(object["role"] as? String, "tool")
        XCTAssertEqual(object["content"] as? String, "42")
        XCTAssertEqual(object["tool_call_id"] as? String, "call_abc")
        XCTAssertNil(object["tool_calls"], "should be absent, not null")
    }

    func testUserMessageEncodesNeitherToolCallIdNorToolCalls() throws {
        let message = Chat.Message.user("hi")
        let data = try JSONEncoder().encode(message)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(object["role"] as? String, "user")
        XCTAssertEqual(object["content"] as? String, "hi")
        XCTAssertNil(object["tool_call_id"])
        XCTAssertNil(object["tool_calls"])
    }

    func testToolMessageWithoutCallIdFailsEncode() {
        let bad = Chat.Message(role: .tool, content: .text("42"), toolCallId: nil)
        XCTAssertThrowsError(try JSONEncoder().encode(bad)) { error in
            guard case EncodingError.invalidValue = error else {
                return XCTFail("expected EncodingError.invalidValue, got \(error)")
            }
        }
    }

    func testNonToolRoleWithToolCallIdFailsEncode() {
        let bad = Chat.Message(role: .assistant, content: .text("hi"), toolCallId: "call_abc")
        XCTAssertThrowsError(try JSONEncoder().encode(bad)) { error in
            guard case EncodingError.invalidValue = error else {
                return XCTFail("expected EncodingError.invalidValue, got \(error)")
            }
        }
    }

    func testNonAssistantWithToolCallsFailsEncode() {
        let bad = Chat.Message(
            role: .user,
            content: .text("hi"),
            toolCalls: [Chat.ToolCall(id: "call_abc", function: .init(name: "x", arguments: "{}"))],
        )
        XCTAssertThrowsError(try JSONEncoder().encode(bad)) { error in
            guard case EncodingError.invalidValue = error else {
                return XCTFail("expected EncodingError.invalidValue, got \(error)")
            }
        }
    }

    func testRequestEncodesToolsWithOpenAIShape() throws {
        let tool = Chat.Tool(
            name: "get_weather",
            description: "Look up current weather",
            parameters: .init(
                properties: [
                    "location": .init(type: "string", description: "City name or zip"),
                    "units":    .init(type: "string", description: "celsius or fahrenheit"),
                ],
                required: ["location"],
            ),
        )
        let request = Chat.Request(
            model: Model("fixture-model-small"),
            messages: [.user("what's the weather in SF?")],
            tools: [tool],
        )

        let data = try JSONEncoder().encode(request)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let toolsArray = try XCTUnwrap(object["tools"] as? [[String: Any]])
        XCTAssertEqual(toolsArray.count, 1)
        XCTAssertEqual(toolsArray[0]["type"] as? String, "function")
        let function = try XCTUnwrap(toolsArray[0]["function"] as? [String: Any])
        XCTAssertEqual(function["name"] as? String, "get_weather")
        XCTAssertEqual(function["description"] as? String, "Look up current weather")
        let parameters = try XCTUnwrap(function["parameters"] as? [String: Any])
        XCTAssertEqual(parameters["type"] as? String, "object")
        XCTAssertEqual(parameters["required"] as? [String], ["location"])
        let properties = try XCTUnwrap(parameters["properties"] as? [String: [String: String]])
        XCTAssertEqual(properties["location"]?["type"], "string")
        XCTAssertEqual(properties["location"]?["description"], "City name or zip")
        XCTAssertEqual(properties["units"]?["type"], "string")
    }

    func testRequestWithoutToolsOmitsToolsField() throws {
        let request = Chat.Request(
            model: Model("fixture-model-small"),
            messages: [.user("hi")],
        )
        let data = try JSONEncoder().encode(request)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(object["tools"], "should be absent when not passed, not null or empty array")
    }

    func testParametersWithEmptyRequiredOmitsTheField() throws {
        let parameters = Chat.Tool.Parameters(
            properties: ["x": .init(type: "string", description: "y")],
            required: [],
        )
        let data = try JSONEncoder().encode(parameters)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["type"] as? String, "object")
        XCTAssertNotNil(object["properties"])
        XCTAssertNil(object["required"], "empty `required` should be omitted, not emitted as []")
    }

    func testPropertySchemaNormalisesTypeToLowercase() {
        let schema = Chat.Tool.PropertySchema(type: "STRING", description: "x")
        XCTAssertEqual(schema.type, "string")
        let extended = Chat.Tool.PropertySchema(type: "MyCustomFormat", description: "x")
        XCTAssertEqual(extended.type, "MyCustomFormat")
    }

    func testStreamChunkDecodesToolCallDelta() throws {
        let json = """
        {
          "id": "chatcmpl-1",
          "object": "chat.completion.chunk",
          "model": "fixture-model-small",
          "choices": [
            {
              "index": 0,
              "delta": {
                "role": "assistant",
                "tool_calls": [
                  {
                    "index": 0,
                    "id": "call_abc",
                    "type": "function",
                    "function": { "name": "get_weather", "arguments": "{\\"loc" }
                  }
                ]
              },
              "finish_reason": null
            }
          ]
        }
        """.data(using: .utf8)!

        let chunk = try JSONDecoder().decode(Chat.StreamChunk.self, from: json)
        XCTAssertEqual(chunk.choices.count, 1)
        let delta = chunk.choices[0].delta
        XCTAssertEqual(delta.role, .assistant)
        XCTAssertNil(delta.content)
        let toolCalls = try XCTUnwrap(delta.toolCalls)
        XCTAssertEqual(toolCalls.count, 1)
        XCTAssertEqual(toolCalls[0].index, 0)
        XCTAssertEqual(toolCalls[0].id, "call_abc")
        XCTAssertEqual(toolCalls[0].type, "function")
        XCTAssertEqual(toolCalls[0].function?.name, "get_weather")
        XCTAssertEqual(toolCalls[0].function?.arguments, "{\"loc")
    }

    func testStreamChunkDecodesArgumentsContinuationWithoutIdOrName() throws {
        let json = """
        {
          "id": "chatcmpl-1",
          "choices": [
            {
              "index": 0,
              "delta": {
                "tool_calls": [
                  { "index": 0, "function": { "arguments": "ation\\":\\"SF\\"}" } }
                ]
              }
            }
          ]
        }
        """.data(using: .utf8)!

        let chunk = try JSONDecoder().decode(Chat.StreamChunk.self, from: json)
        let toolCalls = try XCTUnwrap(chunk.choices[0].delta.toolCalls)
        XCTAssertEqual(toolCalls[0].index, 0)
        XCTAssertNil(toolCalls[0].id)
        XCTAssertNil(toolCalls[0].type)
        XCTAssertNil(toolCalls[0].function?.name)
        XCTAssertEqual(toolCalls[0].function?.arguments, "ation\":\"SF\"}")
    }

    func testStreamChunkPlainTextDeltaStillDecodes() throws {
        let json = """
        {
          "id": "chatcmpl-1",
          "choices": [
            { "index": 0, "delta": { "content": "hi" }, "finish_reason": null }
          ]
        }
        """.data(using: .utf8)!

        let chunk = try JSONDecoder().decode(Chat.StreamChunk.self, from: json)
        XCTAssertEqual(chunk.choices[0].delta.content, "hi")
        XCTAssertNil(chunk.choices[0].delta.toolCalls)
    }

    func testToolCallRoundTripsThroughCodable() throws {
        let original = Chat.ToolCall(
            id: "call_abc",
            function: .init(name: "get_weather", arguments: #"{"location":"SF"}"#),
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Chat.ToolCall.self, from: data)
        XCTAssertEqual(decoded.id, original.id)
        XCTAssertEqual(decoded.type, "function")
        XCTAssertEqual(decoded.function.name, original.function.name)
        XCTAssertEqual(decoded.function.arguments, original.function.arguments)
    }

    func testTextContentEncodesAsBareString() throws {
        let message = Chat.Message.user("hello")
        let data = try JSONEncoder().encode(message)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["content"] as? String, "hello",
                       "text-only messages must encode as a bare string, not a one-element array")
    }

    func testMultimodalUserMessageEncodesAsTypedPartsArray() throws {
        let image = Chat.Message.Content.ImageData(mediaType: "image/png", base64: "iVBOR")
        let message = Chat.Message.user(parts: [
            .text("describe this:"),
            .image(image),
        ])

        let data = try JSONEncoder().encode(message)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let content = try XCTUnwrap(object["content"] as? [[String: Any]])
        XCTAssertEqual(content.count, 2)

        XCTAssertEqual(content[0]["type"] as? String, "text")
        XCTAssertEqual(content[0]["text"] as? String, "describe this:")

        XCTAssertEqual(content[1]["type"] as? String, "image_url")
        let imageURL = try XCTUnwrap(content[1]["image_url"] as? [String: Any])
        XCTAssertEqual(imageURL["url"] as? String, "data:image/png;base64,iVBOR")
    }

    func testMultimodalContentRoundTripsThroughCodable() throws {
        let original = Chat.Message.user(parts: [
            .text("look:"),
            .image(.init(mediaType: "image/jpeg", base64: "/9j/abc")),
        ])
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Chat.Message.self, from: data)
        XCTAssertEqual(decoded, original)

        guard case .parts(let parts) = decoded.content else {
            return XCTFail("expected .parts, got \(decoded.content)")
        }
        XCTAssertEqual(parts.count, 2)
        if case .image(let img) = parts[1] {
            XCTAssertEqual(img.mediaType, "image/jpeg")
            XCTAssertEqual(img.base64, "/9j/abc")
            XCTAssertEqual(img.dataURL, "data:image/jpeg;base64,/9j/abc")
        } else {
            XCTFail("expected .image part, got \(parts[1])")
        }
    }

    func testContentTextAccessorConcatenatesTextParts() {
        let multimodal = Chat.Message.Content.parts([
            .text("hello "),
            .image(.init(mediaType: "image/png", base64: "x")),
            .text("world"),
        ])
        XCTAssertEqual(multimodal.text, "hello world")
        XCTAssertEqual(Chat.Message.Content.text("plain").text, "plain")
    }

    func testNonDataImageURLFailsDecode() {
        let json = """
        {
          "role": "user",
          "content": [
            { "type": "image_url", "image_url": { "url": "https://example.com/cat.png" } }
          ]
        }
        """.data(using: .utf8)!
        XCTAssertThrowsError(try JSONDecoder().decode(Chat.Message.self, from: json)) { error in
            guard case DecodingError.dataCorrupted = error else {
                return XCTFail("expected DecodingError.dataCorrupted, got \(error)")
            }
        }
    }

    func testUnknownContentPartTypeFailsDecode() {
        let json = """
        {
          "role": "user",
          "content": [
            { "type": "document", "document": { "id": "doc_abc" } }
          ]
        }
        """.data(using: .utf8)!
        XCTAssertThrowsError(try JSONDecoder().decode(Chat.Message.self, from: json))
    }

    func testRequestEncodesUserField() throws {
        let request = Chat.Request(
            model: Model("fixture-model-large"),
            messages: [.user("hi")],
            user: "firebase-uid-abc",
        )
        let data = try JSONEncoder().encode(request)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["user"] as? String, "firebase-uid-abc")
    }

    func testRequestWithoutUserOmitsTheField() throws {
        let request = Chat.Request(
            model: Model("fixture-model-large"),
            messages: [.user("hi")],
        )
        let data = try JSONEncoder().encode(request)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertNil(object["user"], "user should be absent when not passed, not null or empty string")
    }

    func testRequestUserEmptyStringFailsEncode() {
        let request = Chat.Request(
            model: Model("fixture-model-large"),
            messages: [.user("hi")],
            user: "",
        )
        XCTAssertThrowsError(try JSONEncoder().encode(request)) { error in
            guard case EncodingError.invalidValue = error else {
                return XCTFail("expected EncodingError.invalidValue, got \(error)")
            }
        }
    }

    func testRequestUserOversizedFailsEncode() {
        let oversized = String(repeating: "a", count: 257)
        let request = Chat.Request(
            model: Model("fixture-model-large"),
            messages: [.user("hi")],
            user: oversized,
        )
        XCTAssertThrowsError(try JSONEncoder().encode(request)) { error in
            guard case EncodingError.invalidValue = error else {
                return XCTFail("expected EncodingError.invalidValue, got \(error)")
            }
        }
    }

    func testRequestUserAtBoundaryEncodes() throws {
        let atBoundary = String(repeating: "a", count: 256)
        let request = Chat.Request(
            model: Model("fixture-model-large"),
            messages: [.user("hi")],
            user: atBoundary,
        )
        let data = try JSONEncoder().encode(request)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(object["user"] as? String, atBoundary)
    }

    func testUsageDecodesCacheAndReasoningFields() throws {
        let json = """
        {
          "prompt_tokens": 100,
          "completion_tokens": 50,
          "total_tokens": 150,
          "cache_creation_tokens": 30,
          "cache_read_tokens": 20,
          "reasoning_tokens": 10
        }
        """.data(using: .utf8)!
        let usage = try JSONDecoder().decode(Chat.Response.Usage.self, from: json)
        XCTAssertEqual(usage.promptTokens, 100)
        XCTAssertEqual(usage.completionTokens, 50)
        XCTAssertEqual(usage.totalTokens, 150)
        XCTAssertEqual(usage.cacheCreationTokens, 30)
        XCTAssertEqual(usage.cacheReadTokens, 20)
        XCTAssertEqual(usage.reasoningTokens, 10)
    }

    func testUsageDecodesWithoutCacheOrReasoningFieldsAsZero() throws {
        let json = """
        {
          "prompt_tokens": 100,
          "completion_tokens": 50,
          "total_tokens": 150
        }
        """.data(using: .utf8)!
        let usage = try JSONDecoder().decode(Chat.Response.Usage.self, from: json)
        XCTAssertEqual(usage.cacheCreationTokens, 0)
        XCTAssertEqual(usage.cacheReadTokens, 0)
        XCTAssertEqual(usage.reasoningTokens, 0)
    }
}
