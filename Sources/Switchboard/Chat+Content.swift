import Foundation

extension Chat.Message {
    public enum Content: Codable, Sendable, Hashable {
        case text(String)
        case parts([Part])

        public var text: String {
            switch self {
            case .text(let s): return s
            case .parts(let parts):
                return parts.compactMap {
                    if case .text(let t) = $0 { return t }
                    return nil
                }.joined()
            }
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let string = try? container.decode(String.self) {
                self = .text(string)
            } else {
                self = .parts(try container.decode([Part].self))
            }
        }

        public func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .text(let string):
                try container.encode(string)
            case .parts(let parts):
                try container.encode(parts)
            }
        }

        public enum Part: Codable, Sendable, Hashable {
            case text(String)
            case image(ImageData)

            private enum CodingKeys: String, CodingKey {
                case type, text
                case imageURL = "image_url"
            }

            private struct ImageURLPayload: Codable, Hashable {
                let url: String
            }

            public func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                switch self {
                case .text(let string):
                    try container.encode("text", forKey: .type)
                    try container.encode(string, forKey: .text)
                case .image(let image):
                    try container.encode("image_url", forKey: .type)
                    try container.encode(ImageURLPayload(url: image.dataURL), forKey: .imageURL)
                }
            }

            public init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                let type = try container.decode(String.self, forKey: .type)
                switch type {
                case "text":
                    self = .text(try container.decode(String.self, forKey: .text))
                case "image_url":
                    let payload = try container.decode(ImageURLPayload.self, forKey: .imageURL)
                    guard let image = ImageData(dataURL: payload.url) else {
                        let preview = payload.url.prefix(64)
                        let suffix = payload.url.count > 64 ? "… (\(payload.url.count) chars total)" : ""
                        throw DecodingError.dataCorruptedError(
                            forKey: .imageURL,
                            in: container,
                            debugDescription: "Expected a `data:` image URL, got \(preview)\(suffix)",
                        )
                    }
                    self = .image(image)
                default:
                    throw DecodingError.dataCorruptedError(
                        forKey: .type,
                        in: container,
                        debugDescription: "Unknown content part type: \(type)",
                    )
                }
            }
        }

        public struct ImageData: Codable, Sendable, Hashable {
            public let mediaType: String
            public let base64: String

            public init(mediaType: String, base64: String) {
                self.mediaType = mediaType
                self.base64 = base64
            }

            public var dataURL: String {
                "data:\(mediaType);base64,\(base64)"
            }

            init?(dataURL: String) {
                guard dataURL.hasPrefix("data:") else { return nil }
                let body = dataURL.dropFirst("data:".count)
                guard let semicolon = body.firstIndex(of: ";"),
                      let comma = body.firstIndex(of: ","),
                      semicolon < comma else { return nil }
                let mediaType = String(body[..<semicolon])
                let marker = String(body[body.index(after: semicolon)..<comma])
                guard marker == "base64" else { return nil }
                let base64 = String(body[body.index(after: comma)...])
                self.mediaType = mediaType
                self.base64 = base64
            }
        }
    }
}
