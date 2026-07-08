import Foundation
import Combine
import Switchboard
import MLX
import MLXLLM
import MLXLMCommon
import MLXHuggingFace
import Tokenizers

@MainActor
public final class LocalModel: ObservableObject, Identifiable {

    public enum State: Equatable {
        case notDownloaded
        case downloading(progress: Double, downloadedBytes: Int64, totalBytes: Int64)
        case downloaded
        case loading
        case ready
        case failed(message: String)

        public var isReady: Bool {
            if case .ready = self { return true }
            return false
        }
    }

    public let huggingFaceRepoID: String
    public let displayName: String
    public let storageDirectory: URL
    public let provider: ModelProvider

    @Published public private(set) var state: State

    public nonisolated var id: String { huggingFaceRepoID }

    private let directoryName: String?
    private var downloadTask: Task<Void, Never>?
    private var container: ModelContainer?

    public static nonisolated var defaultStorageDirectory: URL {
        FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("SwitchboardLocal/Models")
    }

    public init(
        huggingFaceRepoID: String,
        displayName: String,
        inferenceConfig: InferenceConfig = InferenceConfig(),
        contextLimits: ModelLimits = .localDefault,
        storageDirectory: URL = LocalModel.defaultStorageDirectory,
        directoryName: String? = nil
    ) {
        self.huggingFaceRepoID = huggingFaceRepoID
        self.displayName = displayName
        self.storageDirectory = storageDirectory
        self.directoryName = directoryName
        self.provider = ModelProvider(
            modelName: displayName,
            inferenceConfig: inferenceConfig,
            contextLimits: contextLimits
        )
        let resolvedDirectoryName = directoryName ?? Self.sanitizedDirectoryName(for: huggingFaceRepoID)
        let marker = storageDirectory
            .appendingPathComponent(resolvedDirectoryName)
            .appendingPathComponent(Self.completionMarkerName)
        self.state = FileManager.default.fileExists(atPath: marker.path) ? .downloaded : .notDownloaded
    }

    public var modelDirectory: URL {
        storageDirectory.appendingPathComponent(
            directoryName ?? Self.sanitizedDirectoryName(for: huggingFaceRepoID)
        )
    }

    public func download() {
        switch state {
        case .notDownloaded, .failed:
            break
        case .downloading, .downloaded, .loading, .ready:
            return
        }
        state = .downloading(progress: 0, downloadedBytes: 0, totalBytes: 0)
        downloadTask = Task { await performDownload() }
    }

    public func cancelDownload() {
        downloadTask?.cancel()
        downloadTask = nil
        try? FileManager.default.removeItem(at: modelDirectory)
        state = .notDownloaded
    }

    public func load() async {
        switch state {
        case .downloaded, .failed:
            await loadContainer()
        case .notDownloaded, .downloading, .loading, .ready:
            return
        }
    }

    public func delete() {
        provider.abort()
        try? FileManager.default.removeItem(at: modelDirectory)
        container = nil
        state = .notDownloaded
    }

    private static let completionMarkerName = ".complete"

    private static func sanitizedDirectoryName(for huggingFaceRepoID: String) -> String {
        huggingFaceRepoID
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: " ", with: "_")
    }

    private func loadContainer() async {
        state = .loading
        let modelDir = modelDirectory
        patchTokenizerChatTemplate(in: modelDir)
        do {
            let loaded = try await LLMModelFactory.shared.loadContainer(
                from: modelDir,
                using: #huggingFaceTokenizerLoader()
            )
            try? await loaded.perform { ctx in
                let input = try await ctx.processor.prepare(
                    input: UserInput(messages: [["role": "user", "content": "Hi"]])
                )
                let stream = try MLXLMCommon.generate(
                    input: input,
                    parameters: GenerateParameters(maxTokens: 1, temperature: 0),
                    context: ctx
                )
                for try await _ in stream {}
            }
            GPU.clearCache()
            container = loaded
            provider.configure(container: loaded)
            state = .ready
        } catch {
            state = .failed(message: error.localizedDescription)
        }
    }

    private func patchTokenizerChatTemplate(in modelDir: URL) {
        let configURL = modelDir.appendingPathComponent("tokenizer_config.json")
        guard let data = try? Data(contentsOf: configURL),
              var config = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              config["chat_template"] == nil
        else { return }

        let chatTemplate =
            "{% for message in messages %}" +
            "{{- '<|im_start|>' + message['role'] + '\n' + message['content'] + '<|im_end|>\n' }}" +
            "{% endfor %}" +
            "{% if add_generation_prompt %}{{- '<|im_start|>assistant\n' }}{% endif %}"
        config["chat_template"] = chatTemplate

        guard let patched = try? JSONSerialization.data(withJSONObject: config, options: .prettyPrinted) else { return }
        try? patched.write(to: configURL)
    }

    private func performDownload() async {
        do {
            let assets = try await HFModelHost.list(hfRepoID: huggingFaceRepoID)
            let totalBytes = assets.reduce(0) { $0 + Int64($1.size) }

            let modelDir = modelDirectory
            try FileManager.default.createDirectory(at: modelDir, withIntermediateDirectories: true)

            let existingBytes: Int64 = assets
                .filter { FileManager.default.fileExists(atPath: modelDir.appendingPathComponent($0.name).path) }
                .reduce(0) { $0 + Int64($1.size) }

            let estimatedTotal = totalBytes > 0 ? totalBytes : max(existingBytes, 1)
            let tracker = ProgressTracker(initial: existingBytes, total: estimatedTotal)
            state = .downloading(
                progress: Double(existingBytes) / Double(estimatedTotal),
                downloadedBytes: existingBytes,
                totalBytes: estimatedTotal
            )

            let pending = assets.filter {
                !FileManager.default.fileExists(atPath: modelDir.appendingPathComponent($0.name).path)
            }

            try await withThrowingTaskGroup(of: Void.self) { group in
                for asset in pending {
                    try Task.checkCancellation()
                    let dest = modelDir.appendingPathComponent(asset.name)
                    group.addTask {
                        try await HFModelHost.download(asset, hfRepoID: self.huggingFaceRepoID, to: dest) { bytesReceived in
                            Task {
                                if let update = await tracker.add(bytesReceived) {
                                    await MainActor.run { [weak self] in
                                        self?.state = .downloading(
                                            progress: update.progress,
                                            downloadedBytes: update.downloaded,
                                            totalBytes: estimatedTotal
                                        )
                                    }
                                }
                            }
                        }
                    }
                }
                try await group.waitForAll()
            }

            try await Task.detached(priority: .userInitiated) {
                try LocalModel.reassemblePartFiles(in: modelDir)
            }.value

            FileManager.default.createFile(
                atPath: modelDir.appendingPathComponent(Self.completionMarkerName).path,
                contents: nil
            )
            await loadContainer()

        } catch is CancellationError {
            state = .notDownloaded
        } catch {
            state = .failed(message: error.localizedDescription)
        }
    }

    nonisolated static func reassemblePartFiles(in dir: URL) throws {
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        var partGroups: [String: [URL]] = [:]
        for name in contents {
            guard name.contains(".safetensors.part") else { continue }
            if let dotPart = name.range(of: ".part", options: .backwards) {
                let base = String(name[..<dotPart.lowerBound])
                partGroups[base, default: []].append(dir.appendingPathComponent(name))
            }
        }
        guard !partGroups.isEmpty else { return }

        for (base, parts) in partGroups {
            let sorted = parts.sorted { $0.lastPathComponent < $1.lastPathComponent }
            let dest = dir.appendingPathComponent(base)

            FileManager.default.createFile(atPath: dest.path, contents: nil)
            let out = try FileHandle(forWritingTo: dest)
            defer { try? out.close() }

            let chunk = 4 * 1024 * 1024
            for partURL in sorted {
                let input = try FileHandle(forReadingFrom: partURL)
                defer { try? input.close() }
                while true {
                    let data = input.readData(ofLength: chunk)
                    if data.isEmpty { break }
                    out.write(data)
                }
                try FileManager.default.removeItem(at: partURL)
            }
        }
    }
}
