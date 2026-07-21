import Foundation
import SwitchboardNative

public final class InferenceProvider: RawGenerationProvider, @unchecked Sendable {
    public let endUserID: String

    public let supportsVision: Bool
    public private(set) var lastUsage: GenerationUsage?

    private let client: Client
    private let catalogContextWindow: Int?
    private var currentTask: Task<Void, Never>?

    public var contextLimits: ModelLimits {
        guard let window = catalogContextWindow else { return .remoteDefault }
        return ModelLimits(contextWindow: window, budgetTokens: ModelLimits.remoteDefault.budgetTokens)
    }
    public var preferredToolCallMode: ToolCallMode { .native }

    public init(
        apiKey: String,
        endUserID: String,
        baseURL: URL = Client.defaultBaseURL,
        supportsVision: Bool = false,
        contextWindow: Int? = nil,
        urlSession: URLSession = .shared
    ) throws {
        guard !endUserID.isEmpty else { throw ProviderError.missingEndUserID }
        self.endUserID = endUserID
        self.supportsVision = supportsVision
        self.catalogContextWindow = contextWindow
        let clientBaseURL = baseURL.lastPathComponent == "v1"
            ? baseURL.deletingLastPathComponent()
            : baseURL
        self.client = Client(apiKey: apiKey, baseURL: clientBaseURL, urlSession: urlSession)
    }

    public func generate(_ body: RouterBody) -> AsyncThrowingStream<GenerationChunk, Error> {
        AsyncThrowingStream { continuation in
            let router = SwitchboardRouter(
                userId: endUserID,
                time: Self.timestampFormatter.string(from: Date()),
                idempotencyKey: UUID().uuidString,
                kind: body,
            )
            let task = Task {
                self.lastUsage = nil
                var capturedUsage: GenerationUsage?
                var completed = false
                do {
                    var reducer = try NativeStreamDecoding.reducer(for: body)
                    for try await event in self.client.streamInference(router) {
                        try Task.checkCancellation()
                        let reduction = reducer.reduce(event: event)
                        if let streamError = reduction.streamError {
                            continuation.finish(throwing: ProviderErrorTranslation.translate(streamError))
                            return
                        }
                        for chunk in reduction.chunks {
                            continuation.yield(chunk)
                        }
                        if let usage = reduction.usage { capturedUsage = usage }
                        if reduction.completed { completed = true }
                    }
                    self.lastUsage = capturedUsage
                    if !completed && !NativeStreamDecoding.requiresDoneSentinel(body) {
                        continuation.finish(throwing: ProviderErrorTranslation.translate(SwitchboardError.streamTruncated))
                        return
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch let error as SwitchboardError {
                    continuation.finish(throwing: ProviderErrorTranslation.translate(error))
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            self.currentTask = task
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    public func abort() {
        currentTask?.cancel()
        currentTask = nil
    }

    private static let timestampFormatter = ISO8601DateFormatter()
}
