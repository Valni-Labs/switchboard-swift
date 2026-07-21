import Foundation
import SwitchboardNative

public struct UsageRecord: Codable, Sendable, Hashable {
    public var id: Int
    public var at: Int
    public var endUserId: String?
    public var modelId: String
    public var providerId: String
    public var promptTokens: Int
    public var completionTokens: Int
    public var cacheCreationTokens: Int
    public var cacheReadTokens: Int
    public var reasoningTokens: Int
    public var costMicroCents: Int

    enum CodingKeys: String, CodingKey {
        case id
        case at
        case endUserId = "end_user_id"
        case modelId = "model_id"
        case providerId = "provider_id"
        case promptTokens = "prompt_tokens"
        case completionTokens = "completion_tokens"
        case cacheCreationTokens = "cache_creation_tokens"
        case cacheReadTokens = "cache_read_tokens"
        case reasoningTokens = "reasoning_tokens"
        case costMicroCents = "cost_micro_cents"
    }

    public init(id: Int, at: Int, endUserId: String? = nil, modelId: String, providerId: String, promptTokens: Int, completionTokens: Int, cacheCreationTokens: Int, cacheReadTokens: Int, reasoningTokens: Int, costMicroCents: Int) {
        self.id = id
        self.at = at
        self.endUserId = endUserId
        self.modelId = modelId
        self.providerId = providerId
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.cacheCreationTokens = cacheCreationTokens
        self.cacheReadTokens = cacheReadTokens
        self.reasoningTokens = reasoningTokens
        self.costMicroCents = costMicroCents
    }
}

public struct UsagePage: Codable, Sendable, Hashable {
    public var companyId: String
    public var records: [UsageRecord]
    public var nextBeforeAt: Int?
    public var nextBeforeId: Int?

    enum CodingKeys: String, CodingKey {
        case companyId = "company_id"
        case records
        case nextBeforeAt = "next_before_at"
        case nextBeforeId = "next_before_id"
    }

    public init(companyId: String, records: [UsageRecord], nextBeforeAt: Int? = nil, nextBeforeId: Int? = nil) {
        self.companyId = companyId
        self.records = records
        self.nextBeforeAt = nextBeforeAt
        self.nextBeforeId = nextBeforeId
    }
}

public struct ModelsPage: Codable, Sendable {
    public var models: [ModelRecord]
    public var prices: [String: ModelRecordPrice]

    public init(models: [ModelRecord], prices: [String: ModelRecordPrice]) {
        self.models = models
        self.prices = prices
    }
}

public struct BalancePage: Codable, Sendable, Hashable {
    public var companyId: String
    public var balanceMicroCents: Int

    enum CodingKeys: String, CodingKey {
        case companyId = "company_id"
        case balanceMicroCents = "balance_micro_cents"
    }

    public init(companyId: String, balanceMicroCents: Int) {
        self.companyId = companyId
        self.balanceMicroCents = balanceMicroCents
    }
}

public struct ErrorEnvelope: Codable, Sendable, Hashable {
    public var code: String
    public var error: String

    public init(code: String, error: String) {
        self.code = code
        self.error = error
    }
}
