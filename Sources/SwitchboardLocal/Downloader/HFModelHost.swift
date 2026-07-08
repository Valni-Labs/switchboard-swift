import Foundation
import Switchboard

enum HFModelHost {

    struct Asset {
        let name: String
        let size: Int
    }

    static func list(hfRepoID: String) async throws -> [Asset] {
        let entries = try await treeFiles(repo: hfRepoID, path: "")
        return entries
            .filter { $0.type == "file" && isLLMFile($0.path) }
            .map { Asset(name: $0.path, size: $0.size) }
    }

    static func download(
        _ asset: Asset,
        hfRepoID: String,
        to dest: URL,
        onProgress: @escaping @Sendable (Int64) -> Void
    ) async throws {
        try await download(repo: hfRepoID, path: asset.name, to: dest, onProgress: onProgress)
    }

    private static var token: String? { nil }

    private struct TreeEntry: Decodable {
        let path: String
        let size: Int
        let type: String
    }

    private static func treeFiles(repo: String, path: String) async throws -> [TreeEntry] {
        let pathSuffix = path.isEmpty ? "" : "/\(path)"
        let url = URL(string: "https://huggingface.co/api/models/\(repo)/tree/main\(pathSuffix)")!
        var request = URLRequest(url: url)
        if let t = token {
            request.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization")
        } else {
            ValniLog.download.warning("HF token not configured — request to \(repo, privacy: .public) will be unauthenticated")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let body = String(data: data, encoding: .utf8)?.prefix(200) ?? ""
            ValniLog.download.error("HF tree API \(http.statusCode, privacy: .public) for \(repo, privacy: .public): \(body, privacy: .public)")
            throw HFError.httpError(http.statusCode, String(body))
        }
        return try JSONDecoder().decode([TreeEntry].self, from: data)
    }

    private static func download(
        repo: String,
        path: String,
        to dest: URL,
        onProgress: @escaping @Sendable (Int64) -> Void
    ) async throws {
        let url = URL(string: "https://huggingface.co/\(repo)/resolve/main/\(path)")!
        let handler = DownloadHandler(destination: dest, onProgress: onProgress)
        let session = URLSession(configuration: .default, delegate: handler, delegateQueue: nil)
        var request = URLRequest(url: url)
        if let t = token { request.setValue("Bearer \(t)", forHTTPHeaderField: "Authorization") }
        ValniLog.download.debug("HFModelHost GET \(url.lastPathComponent, privacy: .public)")
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                handler.continuation = cont
                session.downloadTask(with: request).resume()
            }
        } onCancel: {
            session.invalidateAndCancel()
        }
    }

    private static func isLLMFile(_ name: String) -> Bool {
        if name.hasSuffix(".zip") { return false }
        let ext = URL(fileURLWithPath: name).pathExtension
        return ["safetensors", "json", "model"].contains(ext)
            || name.contains(".safetensors.part")
    }
}

enum HFError: LocalizedError {
    case httpError(Int, String)

    var errorDescription: String? {
        switch self {
        case .httpError(401, _): return "Model download is temporarily unavailable. Please try again later."
        case .httpError(403, _): return "Model download is temporarily unavailable. Please try again later."
        case .httpError(404, _): return "Model files could not be found. Please try again later."
        case .httpError(429, _): return "Download servers are busy. Please wait a few minutes and try again."
        case .httpError(let code, _): return "Download failed (error \(code)). Please try again later."
        }
    }
}
