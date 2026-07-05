import XCTest
@testable import Switchboard

final class PromptCachingWireTests: XCTestCase {

    func testSystemPromptCarriesCacheBreakpoint() throws {
        let body = try AnthropicMessagesAdapter.buildRequestBody(
            messages: [
                ChatMessage(role: .system, text: "you are an engineer"),
                ChatMessage(role: .user, text: "list files"),
            ],
            tools: [],
            modelID: "fixture-model-large",
            endUserID: nil
        )

        let wire = try encodeToDictionary(body)
        let system = try XCTUnwrap(wire["system"] as? [[String: Any]])
        XCTAssertEqual(system.count, 1)
        XCTAssertEqual(system[0]["type"] as? String, "text")
        XCTAssertEqual(system[0]["text"] as? String, "you are an engineer")
        XCTAssertEqual((system[0]["cache_control"] as? [String: Any])?["type"] as? String, "ephemeral")
    }

    func testLastMessageBlockCarriesCacheBreakpointAndEarlierBlocksDoNot() throws {
        let body = try AnthropicMessagesAdapter.buildRequestBody(
            messages: [
                ChatMessage(role: .user, text: "read both"),
                ChatMessage(
                    role: .assistant,
                    content: .text("reading"),
                    toolCalls: [Chat.ToolCall(id: "c1", function: .init(name: "read_file", arguments: #"{"path": "a"}"#))]
                ),
                .tool(callID: "c1", result: "alpha"),
            ],
            tools: [],
            modelID: "fixture-model-large",
            endUserID: nil
        )

        let wire = try encodeToDictionary(body)
        let messages = try XCTUnwrap(wire["messages"] as? [[String: Any]])
        let allBlocks = messages.flatMap { $0["content"] as? [[String: Any]] ?? [] }
        let markedBlocks = allBlocks.filter { $0["cache_control"] != nil }
        XCTAssertEqual(markedBlocks.count, 1, "Exactly one message block carries the breakpoint")

        let lastBlock = try XCTUnwrap((messages.last?["content"] as? [[String: Any]])?.last)
        XCTAssertEqual((lastBlock["cache_control"] as? [String: Any])?["type"] as? String, "ephemeral")
        XCTAssertEqual(lastBlock["type"] as? String, "tool_result",
                       "The marker rides on the block without changing its shape")
        XCTAssertEqual(lastBlock["tool_use_id"] as? String, "c1")
    }

    func testNoSystemPromptOmitsSystemField() throws {
        let body = try AnthropicMessagesAdapter.buildRequestBody(
            messages: [ChatMessage(role: .user, text: "hi")],
            tools: [],
            modelID: "fixture-model-large",
            endUserID: nil
        )

        let wire = try encodeToDictionary(body)
        XCTAssertNil(wire["system"])
    }

    private func encodeToDictionary(_ value: some Encodable) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}
