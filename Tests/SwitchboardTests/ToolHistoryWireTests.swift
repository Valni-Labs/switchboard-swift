import XCTest
@testable import Switchboard

final class ToolHistoryWireTests: XCTestCase {

    func testAnthropicAssistantToolCallsBecomeToolUseBlocks() throws {
        let body = try AnthropicMessagesAdapter.buildRequestBody(
            messages: [
                ChatMessage(role: .system, text: "system"),
                ChatMessage(role: .user, text: "list files"),
                ChatMessage(
                    role: .assistant,
                    content: .text("running the command"),
                    toolCalls: [Chat.ToolCall(id: "c1", function: .init(name: "bash", arguments: #"{"command": "ls"}"#))]
                ),
                .tool(callID: "c1", result: "file.txt"),
            ],
            tools: [],
            modelID: "fixture-model-large",
            endUserID: nil
        )

        let wire = try encodeToDictionary(body)
        let messages = try XCTUnwrap(wire["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.count, 3)

        let assistant = messages[1]
        XCTAssertEqual(assistant["role"] as? String, "assistant")
        let assistantBlocks = try XCTUnwrap(assistant["content"] as? [[String: Any]])
        XCTAssertEqual(assistantBlocks.map { $0["type"] as? String }, ["text", "tool_use"])
        XCTAssertEqual(assistantBlocks[1]["id"] as? String, "c1")
        XCTAssertEqual(assistantBlocks[1]["name"] as? String, "bash")
        XCTAssertEqual((assistantBlocks[1]["input"] as? [String: Any])?["command"] as? String, "ls")

        let reply = messages[2]
        XCTAssertEqual(reply["role"] as? String, "user")
        let replyBlocks = try XCTUnwrap(reply["content"] as? [[String: Any]])
        XCTAssertEqual(replyBlocks.count, 1)
        XCTAssertEqual(replyBlocks[0]["type"] as? String, "tool_result")
        XCTAssertEqual(replyBlocks[0]["tool_use_id"] as? String, "c1")
        XCTAssertEqual(replyBlocks[0]["content"] as? String, "file.txt")
    }

    func testAnthropicConsecutiveToolResultsMergeIntoOneUserTurn() throws {
        let body = try AnthropicMessagesAdapter.buildRequestBody(
            messages: [
                ChatMessage(role: .user, text: "read both"),
                ChatMessage(
                    role: .assistant,
                    content: .text(""),
                    toolCalls: [
                        Chat.ToolCall(id: "c1", function: .init(name: "read_file", arguments: #"{"path": "a"}"#)),
                        Chat.ToolCall(id: "c2", function: .init(name: "read_file", arguments: #"{"path": "b"}"#)),
                    ]
                ),
                .tool(callID: "c1", result: "alpha"),
                .tool(callID: "c2", result: "beta"),
            ],
            tools: [],
            modelID: "fixture-model-large",
            endUserID: nil
        )

        let wire = try encodeToDictionary(body)
        let messages = try XCTUnwrap(wire["messages"] as? [[String: Any]])
        XCTAssertEqual(messages.map { $0["role"] as? String }, ["user", "assistant", "user"],
                       "Anthropic requires alternating turns — consecutive tool results share one user message")

        let assistantBlocks = try XCTUnwrap(messages[1]["content"] as? [[String: Any]])
        XCTAssertEqual(assistantBlocks.map { $0["type"] as? String }, ["tool_use", "tool_use"],
                       "An empty assistant text block must not ride along with tool_use blocks")

        let replyBlocks = try XCTUnwrap(messages[2]["content"] as? [[String: Any]])
        XCTAssertEqual(replyBlocks.map { $0["tool_use_id"] as? String }, ["c1", "c2"])
    }

    func testAnthropicMalformedToolArgumentsThrowRequestInvalid() {
        XCTAssertThrowsError(try AnthropicMessagesAdapter.buildRequestBody(
            messages: [
                ChatMessage(
                    role: .assistant,
                    content: .text(""),
                    toolCalls: [Chat.ToolCall(id: "c1", function: .init(name: "bash", arguments: #"{"command""#))]
                ),
            ],
            tools: [],
            modelID: "fixture-model-large",
            endUserID: nil
        )) { error in
            guard case ProviderError.requestInvalid = error else {
                return XCTFail("Expected requestInvalid, got \(error)")
            }
        }
    }

    func testGenericWireMessageEncodesToolCallsAndToolReplies() throws {
        let assistant = GenericWireMessage(from: ChatMessage(
            role: .assistant,
            content: .text("calling"),
            toolCalls: [Chat.ToolCall(id: "c1", function: .init(name: "bash", arguments: #"{"command": "ls"}"#))]
        ))
        let assistantWire = try encodeToDictionary(assistant)
        let toolCalls = try XCTUnwrap(assistantWire["tool_calls"] as? [[String: Any]])
        XCTAssertEqual(toolCalls[0]["id"] as? String, "c1")
        XCTAssertEqual(toolCalls[0]["type"] as? String, "function")
        XCTAssertEqual((toolCalls[0]["function"] as? [String: Any])?["name"] as? String, "bash")
        XCTAssertNil(assistantWire["tool_call_id"])

        let reply = GenericWireMessage(from: .tool(callID: "c1", result: "file.txt"))
        let replyWire = try encodeToDictionary(reply)
        XCTAssertEqual(replyWire["role"] as? String, "tool")
        XCTAssertEqual(replyWire["tool_call_id"] as? String, "c1")
        XCTAssertEqual(replyWire["content"] as? String, "file.txt")

        let plain = GenericWireMessage(from: ChatMessage(role: .user, text: "hi"))
        let plainWire = try encodeToDictionary(plain)
        XCTAssertNil(plainWire["tool_calls"])
        XCTAssertNil(plainWire["tool_call_id"])
    }

    private func encodeToDictionary(_ value: some Encodable) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
