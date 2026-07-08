import XCTest
@testable import Switchboard

final class ToolHistoryWireTests: XCTestCase {

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
