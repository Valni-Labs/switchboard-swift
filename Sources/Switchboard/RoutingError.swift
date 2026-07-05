import Foundation

public enum RoutingError: LocalizedError {
    case classifiersNotReady
    case imagesNotSupportedByModel(modelID: String)

    public var errorDescription: String? {
        switch self {
        case .classifiersNotReady:
            return "Valni isn't ready yet. Please wait for setup to complete in Settings."
        case .imagesNotSupportedByModel(let modelID):
            return "\(modelID) can't read images. Switch to a vision-capable model to send attachments."
        }
    }
}
