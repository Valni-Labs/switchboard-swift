import Foundation

actor ProgressTracker {
    private var downloaded: Int64
    private let total: Int64
    private var lastReported: Double = 0

    init(initial: Int64, total: Int64) {
        downloaded = initial
        self.total = total
    }

    struct Update { let progress: Double; let downloaded: Int64 }

    func add(_ bytes: Int64) -> Update? {
        downloaded += bytes
        let progress = total > 0 ? Double(downloaded) / Double(total) : 0
        guard progress - lastReported >= 0.001 else { return nil }
        lastReported = progress
        return Update(progress: progress, downloaded: downloaded)
    }
}
