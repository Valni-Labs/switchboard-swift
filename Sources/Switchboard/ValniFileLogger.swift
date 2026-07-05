import Foundation

public final class ValniFileLogger: @unchecked Sendable {

    public static let shared = ValniFileLogger()

    private let fileURL: URL
    private let queue = DispatchQueue(label: "com.benovi.valni.file-logger", qos: .utility)

    private init() {
        let dir = FileManager.default
            .urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Logs/Valni", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("integration.log")
    }

    public func log(_ line: String) {
        write("[\(timestamp())] [Valni] \(line)")
    }

    private func timestamp() -> String { ISO8601DateFormatter().string(from: Date()) }

    private func write(_ line: String) {
        #if DEBUG
        let entry = line + "\n"
        queue.async { [fileURL] in
            guard let data = entry.data(using: .utf8) else { return }
            if FileManager.default.fileExists(atPath: fileURL.path) {
                if let handle = try? FileHandle(forWritingTo: fileURL) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    try? handle.close()
                }
            } else {
                try? data.write(to: fileURL, options: .atomic)
            }
        }
        #endif
    }
}
