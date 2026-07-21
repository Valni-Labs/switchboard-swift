import Foundation
import Switchboard
import SwitchboardNative
import os
import MLX
import MLXLLM
import MLXLMCommon
import MLXHuggingFace
import Tokenizers

public final class ModelProvider: Provider, RawGenerationProvider, @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock()
    private var _container: ModelContainer?
    private var _currentTask: Task<Void, Never>?

    public let modelName: String
    public let inferenceConfig: InferenceConfig
    public let contextLimits: ModelLimits
    public var preferredToolCallMode: ToolCallMode { DeprecatedToolCallMode.prompt }
    public var isConfigured: Bool { lock.withLock { _container != nil } }

    public init(
        modelName: String,
        inferenceConfig: InferenceConfig = InferenceConfig(),
        contextLimits: ModelLimits = .localDefault
    ) {
        self.modelName = modelName
        self.inferenceConfig = inferenceConfig
        self.contextLimits = contextLimits
    }

    public func configure(container: ModelContainer) {
        lock.withLock { _container = container }
    }

    public func abort() {
        let task = lock.withLock { () -> Task<Void, Never>? in
            let t = _currentTask
            _currentTask = nil
            return t
        }
        task?.cancel()
    }

    public func generate(_ body: RouterBody) -> AsyncThrowingStream<GenerationChunk, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                let extraction: LocalPromptExtraction
                do {
                    extraction = try LocalPromptExtraction(body: body)
                } catch {
                    continuation.finish(throwing: error)
                    return
                }
                guard let resolvedContainer = self.lock.withLock({ self._container }) else {
                    continuation.finish(throwing: ProviderError.notConfigured("Model is not loaded."))
                    return
                }
                ValniLog.inference.debug("ModelProvider: generate starting, messages=\(extraction.messages.count, privacy: .public)")
                do {
                    let parameters = GenerateParameters(
                        maxTokens: extraction.maxTokens ?? inferenceConfig.maxTokens,
                        temperature: extraction.temperature ?? inferenceConfig.temperature,
                        topP: extraction.topP ?? inferenceConfig.topP,
                        repetitionPenalty: inferenceConfig.repetitionPenalty,
                        repetitionContextSize: inferenceConfig.repetitionContextSize,
                    )
                    try await resolvedContainer.perform { ctx in
                        let input = try await ctx.processor.prepare(input: UserInput(messages: extraction.messages))
                        let stream = try MLXLMCommon.generate(input: input, parameters: parameters, context: ctx)
                        var tokenCount = 0
                        for try await item in stream {
                            switch item {
                            case .chunk(let text):
                                tokenCount += 1
                                continuation.yield(.text(text))
                            case .info(let info):
                                ValniLog.inference.debug("ModelProvider: generate finished prompt=\(info.promptTokenCount, privacy: .public) generated=\(info.generationTokenCount, privacy: .public) yielded=\(tokenCount, privacy: .public)")
                            case .toolCall(let toolCall):
                                let arguments = toolCall.function.arguments.mapValues { $0.anyValue }
                                if let argumentsData = try? JSONSerialization.data(withJSONObject: arguments),
                                   let argumentsJSON = String(data: argumentsData, encoding: .utf8) {
                                    continuation.yield(.toolCall(
                                        id: UUID().uuidString,
                                        name: toolCall.function.name,
                                        argumentsJSON: argumentsJSON,
                                    ))
                                } else {
                                    ValniLog.inference.error("ModelProvider: native toolCall serialization failed name=\(toolCall.function.name, privacy: .public)")
                                }
                            }
                        }
                    }
                    GPU.clearCache()
                    continuation.finish()
                } catch {
                    ValniLog.inference.error("ModelProvider: generate error \(error.localizedDescription, privacy: .public)")
                    continuation.finish(throwing: error)
                }
            }
            self.lock.withLock { self._currentTask = task }
        }
    }
}

struct LocalPromptExtraction {
    let messages: [[String: String]]
    let maxTokens: Int?
    let temperature: Float?
    let topP: Float?

    init(body: RouterBody) throws {
        switch body {
        case .anthropic(let request):
            var extracted: [[String: String]] = []
            if let system = request.system {
                switch system {
                case .text(let text):
                    extracted.append(["role": "system", "content": text])
                case .blocks(let blocks):
                    let joined = blocks.map(\.text).joined(separator: "\n")
                    if !joined.isEmpty { extracted.append(["role": "system", "content": joined]) }
                }
            }
            for message in request.messages {
                extracted.append(["role": message.role.rawValue, "content": Self.text(of: message.content)])
            }
            messages = extracted
            maxTokens = Int(request.maxTokens)
            temperature = request.temperature.map(Float.init)
            topP = request.topP.map(Float.init)
        case .openaiGeneric(let request):
            messages = request.messages.map { message in
                ["role": message.role.rawValue, "content": Self.text(of: message.content ?? .null)]
            }
            maxTokens = (request.maxCompletionTokens ?? request.maxTokens).map(Int.init)
            temperature = request.temperature.map(Float.init)
            topP = request.topP.map(Float.init)
        case .openaiPro(let request):
            var extracted: [[String: String]] = []
            if let instructions = request.instructions {
                extracted.append(["role": "system", "content": instructions])
            }
            switch request.input {
            case .string(let text):
                extracted.append(["role": "user", "content": text])
            case .array(let items):
                for item in items {
                    guard case .object(let fields) = item,
                          case .string("message")? = fields["type"],
                          case .string(let role)? = fields["role"] else { continue }
                    extracted.append(["role": role, "content": Self.text(of: fields["content"] ?? .null)])
                }
            default:
                break
            }
            messages = extracted
            maxTokens = request.maxOutputTokens.map(Int.init)
            temperature = request.temperature.map(Float.init)
            topP = request.topP.map(Float.init)
        case .google(let request):
            var extracted: [[String: String]] = []
            if let systemInstruction = request.systemInstruction {
                let joined = Self.text(of: systemInstruction.parts)
                if !joined.isEmpty { extracted.append(["role": "system", "content": joined]) }
            }
            for content in request.contents {
                let role = content.role == .model ? "assistant" : "user"
                extracted.append(["role": role, "content": Self.text(of: content.parts)])
            }
            messages = extracted
            maxTokens = request.generationConfig?.maxOutputTokens.map(Int.init)
            temperature = request.generationConfig?.temperature.map(Float.init)
            topP = request.generationConfig?.topP.map(Float.init)
        case .unrecognized(let kind):
            throw ProviderError.requestInvalid(message: "Request kind \"\(kind)\" is not supported by this Switchboard SDK build.")
        }
    }

    private static func text(of parts: [GooglePart]) -> String {
        parts.compactMap { part -> String? in
            guard case .text(let text) = part else { return nil }
            return text
        }.joined(separator: "\n")
    }

    private static func text(of content: SwitchboardJSON) -> String {
        switch content {
        case .string(let text):
            return text
        case .array(let parts):
            return parts.compactMap { part -> String? in
                guard case .object(let fields) = part else { return nil }
                if case .string(let text)? = fields["text"] { return text }
                return nil
            }.joined(separator: "\n")
        default:
            return ""
        }
    }
}
