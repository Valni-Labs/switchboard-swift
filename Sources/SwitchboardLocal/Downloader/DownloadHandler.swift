import Foundation
import Switchboard

enum DownloadError: LocalizedError {
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

final class DownloadHandler: NSObject, URLSessionDownloadDelegate {
    private let destination: URL
    private let onProgress: @Sendable (Int64) -> Void
    var continuation: CheckedContinuation<Void, Error>?
    private var completed = false

    init(destination: URL, onProgress: @escaping @Sendable (Int64) -> Void) {
        self.destination = destination
        self.onProgress = onProgress
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        onProgress(bytesWritten)
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        completed = true
        let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? -1
        ValniLog.download.debug("HTTP \(status, privacy: .public) ← \(downloadTask.originalRequest?.url?.lastPathComponent ?? "?", privacy: .public)")

        if let http = downloadTask.response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            let body = (try? String(contentsOf: location, encoding: .utf8))?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            continuation?.resume(throwing: DownloadError.httpError(http.statusCode, String(body.prefix(200))))
            continuation = nil
            return
        }

        do {
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: location, to: destination)
            continuation?.resume()
        } catch {
            continuation?.resume(throwing: error)
        }
        continuation = nil
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        let from = task.originalRequest?.url?.host ?? "?"
        let to = request.url?.host ?? "?"
        ValniLog.download.debug("Redirect \(from, privacy: .public) → \(to, privacy: .public)")
        if to != from {
            var stripped = request
            stripped.setValue(nil, forHTTPHeaderField: "Authorization")
            completionHandler(stripped)
        } else {
            completionHandler(request)
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard !completed, let error else { return }
        ValniLog.download.error("Download error: \(error.localizedDescription, privacy: .public)")
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled {
            continuation?.resume(throwing: CancellationError())
        } else {
            continuation?.resume(throwing: error)
        }
        continuation = nil
    }
}
