import Foundation
import SwitchboardNative

extension Client {
    static let inferencePath = "/v1/switchboard/inference"

    public func inference(_ router: SwitchboardRouter) async throws -> NativeResponse {
        let urlRequest = try buildURLRequest(path: Self.inferencePath, body: router)
        let (data, response) = try await performData(urlRequest)
        try ensureSuccess(response: response, body: data)
        let decoder = JSONDecoder()
        do {
            switch router.kind {
            case .anthropic:
                return .anthropic(try decoder.decode(AnthropicMessageResponse.self, from: data))
            case .openaiGeneric:
                return .openaiGeneric(try decoder.decode(OpenAIChatResponse.self, from: data))
            case .openaiPro:
                return .openaiPro(try decoder.decode(OpenAIResponsesResponse.self, from: data))
            case .google:
                return .google(try decoder.decode(GoogleGenerateContentResponse.self, from: data))
            case .unrecognized(let kind):
                throw SwitchboardError.unsupportedKind(kind: kind)
            }
        } catch let error as SwitchboardError {
            throw error
        } catch {
            throw SwitchboardError.decodingFailed(underlying: error)
        }
    }

    public func streamInference(_ router: SwitchboardRouter) -> AsyncThrowingStream<NativeStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let streamingRouter = SwitchboardRouter(
                userId: router.userId,
                time: router.time,
                idempotencyKey: router.idempotencyKey,
                kind: router.kind.streaming(),
            )

            let task = Task {
                do {
                    let urlRequest = try self.buildURLRequest(path: Self.inferencePath, body: streamingRouter)
                    let (bytes, response) = try await self.performBytes(urlRequest)
                    if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
                        var collected = Data()
                        for try await byte in bytes {
                            collected.append(byte)
                            if collected.count > Client.maxErrorBodyBytes { break }
                        }
                        try self.ensureSuccess(response: response, body: collected)
                    }
                    let decoder = JSONDecoder()
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        if payload.isEmpty || payload == NativeStreamDecoding.doneSentinel { continue }
                        guard let json = payload.data(using: .utf8) else { continue }
                        let event: NativeStreamEvent
                        do {
                            event = try NativeStreamDecoding.decodeEvent(for: streamingRouter.kind, payload: json, decoder: decoder)
                        } catch let error as SwitchboardError {
                            continuation.finish(throwing: error)
                            return
                        } catch {
                            continuation.finish(throwing: SwitchboardError.decodingFailed(underlying: error))
                            return
                        }
                        continuation.yield(event)
                    }
                    continuation.finish()
                } catch let error as SwitchboardError {
                    continuation.finish(throwing: error)
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: SwitchboardError.transportError(underlying: error))
                }
            }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }
}
