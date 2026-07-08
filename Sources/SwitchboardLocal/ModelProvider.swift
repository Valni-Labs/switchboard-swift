import Foundation
import Switchboard
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

    public func generateRaw(messages: [ChatMessage]) -> AsyncThrowingStream<RawStreamChunk, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                if messages.contains(where: \.hasNonTextContent) {
                    continuation.finish(throwing: RoutingError.imagesNotSupportedByModel(modelID: self.modelName))
                    return
                }
                guard let resolvedContainer = self.lock.withLock({ self._container }) else {
                    continuation.finish(throwing: ProviderError.notConfigured("Model is not loaded."))
                    return
                }
                ValniLog.inference.debug("ModelProvider: generateRaw starting, messages=\(messages.count, privacy: .public)")
                do {
                    let mlxMessages = messages.map { Self.dictFromTextOnlyMessage($0) }
                    try await resolvedContainer.perform { ctx in
                        let input = try await ctx.processor.prepare(input: UserInput(messages: mlxMessages))
                        let stream = try MLXLMCommon.generate(
                            input: input,
                            parameters: GenerateParameters(maxTokens: inferenceConfig.maxTokens, temperature: inferenceConfig.temperature, topP: inferenceConfig.topP, repetitionPenalty: inferenceConfig.repetitionPenalty, repetitionContextSize: inferenceConfig.repetitionContextSize),
                            context: ctx
                        )
                        var tokenCount = 0
                        for try await item in stream {
                            switch item {
                            case .chunk(let s):
                                tokenCount += 1
                                continuation.yield(.text(s))
                            case .info(let info):
                                ValniLog.inference.debug("ModelProvider: generateRaw finished prompt=\(info.promptTokenCount, privacy: .public) generated=\(info.generationTokenCount, privacy: .public) yielded=\(tokenCount, privacy: .public)")
                            case .toolCall(let toolCall):
                                let args = toolCall.function.arguments.mapValues { $0.anyValue }
                                if let argsData = try? JSONSerialization.data(withJSONObject: args),
                                   let argsJSON = String(data: argsData, encoding: .utf8) {
                                    let text = "<tool_call>{\"name\": \"\(toolCall.function.name)\", \"arguments\": \(argsJSON)}</tool_call>"
                                    tokenCount += 1
                                    continuation.yield(.text(text))
                                } else {
                                    ValniLog.inference.error("ModelProvider: native toolCall serialization failed name=\(toolCall.function.name, privacy: .public)")
                                }
                            }
                        }
                    }
                    GPU.clearCache()
                    continuation.finish()
                } catch {
                    ValniLog.inference.error("ModelProvider: generateRaw error \(error.localizedDescription, privacy: .public)")
                    continuation.finish(throwing: error)
                }
            }
            self.lock.withLock { self._currentTask = task }
        }
    }

    private static func dictFromTextOnlyMessage(_ message: ChatMessage) -> [String: String] {
        let text: String
        switch message.content {
        case .text(let s):
            text = s
        case .blocks(let blocks):
            text = blocks.compactMap { block -> String? in
                if case .text(let s) = block { return s }
                return nil
            }.joined(separator: "\n")
        }
        return ["role": message.role.rawValue, "content": text]
    }
}
