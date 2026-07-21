import XCTest
import Switchboard

final class PublicSurfaceTests: XCTestCase {
    func testImportingSwitchboardExposesGeneratedContractTypes() throws {
        let request = AnthropicMessagesRequest(
            model: "claude-sonnet-4-5",
            messages: [AnthropicMessage(role: .user, content: .string("hi"))],
            maxTokens: 16,
        )
        let body = RouterBody.anthropic(request)
        let router = SwitchboardRouter(
            userId: "end-user-1",
            time: "2026-07-16T00:00:00Z",
            idempotencyKey: "idem_1",
            kind: body,
        )
        let encoded = try JSONEncoder().encode(router)
        let decoded = try JSONDecoder().decode(SwitchboardRouter.self, from: encoded)
        XCTAssertEqual(decoded.idempotencyKey, "idem_1")
        guard case .anthropic(let decodedRequest) = decoded.kind else {
            return XCTFail("expected anthropic body, got \(decoded.kind)")
        }
        XCTAssertEqual(decodedRequest.model, "claude-sonnet-4-5")
    }
}
