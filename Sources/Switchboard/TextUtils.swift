import Foundation

public func stripThinkTags(from text: String) -> String {
    var result = text
    while let start = result.range(of: "<think>"),
          let end = result.range(of: "</think>", range: start.upperBound..<result.endIndex) {
        result.removeSubrange(start.lowerBound..<end.upperBound)
    }
    if let start = result.range(of: "<think>") {
        result = String(result[..<start.lowerBound])
    }
    return result.trimmingCharacters(in: .whitespacesAndNewlines)
}
