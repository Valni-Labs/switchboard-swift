import Foundation

extension Client {
    static let inferencePath = "/v1/switchboard/inference"

    public func inference(_ request: Inference.Request) async throws -> Inference.Response {
        let urlRequest = try buildURLRequest(path: Self.inferencePath, body: request)
        let (data, response) = try await performData(urlRequest)
        try ensureSuccess(response: response, body: data)
        do {
            return try JSONDecoder().decode(Inference.Response.self, from: data)
        } catch {
            throw SwitchboardError.decodingFailed(underlying: error)
        }
    }

    public func streamInference(_ request: Inference.Request) -> AsyncThrowingStream<Inference.Frame, Error> {
        AsyncThrowingStream { continuation in
            let streamingRequest = Inference.Request(
                model: request.model,
                messages: request.messages,
                temperature: request.temperature,
                maxTokens: request.maxTokens,
                topP: request.topP,
                stream: true,
                stopSequences: request.stopSequences,
                tools: request.tools,
                user: request.user,
                providerOptions: request.providerOptions,
                includeNative: request.includeNative,
            )

            let task = Task {
                do {
                    let urlRequest = try self.buildURLRequest(path: Self.inferencePath, body: streamingRequest)
                    let (bytes, response) = try await self.performBytes(urlRequest)
                    if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
                        var collected = Data()
                        for try await byte in bytes {
                            collected.append(byte)
                            if collected.count > Client.maxErrorBodyBytes { break }
                        }
                        try self.ensureSuccess(response: response, body: collected)
                    }
                    var sawDone = false
                    let decoder = JSONDecoder()
                    for try await line in bytes.lines {
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        if payload.isEmpty { continue }
                        guard let json = payload.data(using: .utf8) else { continue }
                        let frame: Inference.Frame?
                        do {
                            frame = try Inference.Frame.parse(json, decoder: decoder)
                        } catch {
                            continuation.finish(throwing: SwitchboardError.decodingFailed(underlying: error))
                            return
                        }
                        guard let frame else { continue }
                        if case .error(let code, let message, let detail) = frame {
                            continuation.finish(throwing: SwitchboardError.streamError(code: code, message: message, detail: detail))
                            return
                        }
                        if case .done = frame { sawDone = true }
                        continuation.yield(frame)
                    }
                    if !sawDone {
                        continuation.finish(throwing: SwitchboardError.streamTruncated)
                    } else {
                        continuation.finish()
                    }
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
