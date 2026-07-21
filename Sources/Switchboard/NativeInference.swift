import Foundation
import SwitchboardNative

public enum NativeResponse: Sendable {
    case anthropic(AnthropicMessageResponse)
    case openaiGeneric(OpenAIChatResponse)
    case openaiPro(OpenAIResponsesResponse)
    case google(GoogleGenerateContentResponse)
}

public enum NativeStreamEvent: Sendable {
    case anthropic(AnthropicStreamEvent)
    case openaiGeneric(OpenAIChatChunk)
    case openaiPro(OpenAIResponsesStreamEvent)
    case google(GoogleGenerateContentResponse)
}

extension RouterBody {
    public var modelID: String {
        switch self {
        case .anthropic(let body): return body.model
        case .openaiGeneric(let body): return body.model
        case .openaiPro(let body): return body.model
        case .google(let body): return body.model
        case .unrecognized(let kind): return kind
        }
    }

    public var isStreaming: Bool {
        switch self {
        case .anthropic(let body): return body.stream ?? false
        case .openaiGeneric(let body): return body.stream ?? false
        case .openaiPro(let body): return body.stream ?? false
        case .google(let body): return body.stream ?? false
        case .unrecognized: return false
        }
    }

    public func streaming() -> RouterBody {
        switch self {
        case .anthropic(var body):
            body.stream = true
            return .anthropic(body)
        case .openaiGeneric(var body):
            body.stream = true
            if body.streamOptions == nil {
                body.streamOptions = OpenAIChatRequestStreamOptions(includeUsage: true)
            }
            return .openaiGeneric(body)
        case .openaiPro(var body):
            body.stream = true
            return .openaiPro(body)
        case .google(var body):
            body.stream = true
            return .google(body)
        case .unrecognized:
            return self
        }
    }
}
