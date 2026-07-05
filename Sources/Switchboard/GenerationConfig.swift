import Foundation

public struct ModelLimits: Sendable {
    public let contextWindow: Int
    public let budgetTokens: Int

    public init(contextWindow: Int, budgetTokens: Int) {
        self.contextWindow = contextWindow
        self.budgetTokens = budgetTokens
    }

    public static let localDefault  = ModelLimits(contextWindow: 32_768, budgetTokens: 2_048)
    public static let remoteDefault = ModelLimits(contextWindow: 128_000, budgetTokens: 8_192)
}

public protocol GenerationConfig: Sendable {
    var maxTokens: Int { get }
    var temperature: Float { get }
    var topP: Float { get }
    var repetitionPenalty: Float { get }
    var repetitionContextSize: Int { get }
}

public struct InferenceConfig: GenerationConfig {
    public var maxTokens: Int
    public var temperature: Float
    public var topP: Float
    public var repetitionPenalty: Float
    public var repetitionContextSize: Int

    public init(
        maxTokens: Int = 16_384,
        temperature: Float = 0.7,
        topP: Float = 1.0,
        repetitionPenalty: Float = 1.0,
        repetitionContextSize: Int = 64
    ) {
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.topP = topP
        self.repetitionPenalty = repetitionPenalty
        self.repetitionContextSize = repetitionContextSize
    }
}
