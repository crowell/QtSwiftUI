import Foundation

/// A uniform type identifier and its MIME representation at the Qt desktop boundary.
public struct UTType: Hashable, Codable, Sendable {
    public let identifier: String
    private struct Declaration {
        let mime: String?
        let parent: String?
    }

    private static let declarations: [String: Declaration] = [
        "public.item": .init(mime: nil, parent: nil),
        "public.content": .init(mime: nil, parent: "public.item"),
        "public.data": .init(mime: "application/octet-stream", parent: "public.item"),
        "public.text": .init(mime: nil, parent: "public.data"),
        "public.plain-text": .init(mime: "text/plain", parent: "public.text"),
        "public.utf8-plain-text": .init(mime: "text/plain;charset=utf-8", parent: "public.plain-text"),
        "public.html": .init(mime: "text/html", parent: "public.text"),
        "public.url": .init(mime: "text/uri-list", parent: "public.data"),
        "public.file-url": .init(mime: nil, parent: "public.url"),
        "public.image": .init(mime: nil, parent: "public.data"),
        "public.png": .init(mime: "image/png", parent: "public.image"),
        "public.jpeg": .init(mime: "image/jpeg", parent: "public.image"),
        "com.compuserve.gif": .init(mime: "image/gif", parent: "public.image"),
        "org.webmproject.webp": .init(mime: "image/webp", parent: "public.image"),
        "public.avif": .init(mime: "image/avif", parent: "public.image"),
        "public.heic": .init(mime: "image/heic", parent: "public.image"),
        "public.heif": .init(mime: "image/heif", parent: "public.image"),
        "com.microsoft.bmp": .init(mime: "image/bmp", parent: "public.image"),
        "com.microsoft.ico": .init(mime: "image/vnd.microsoft.icon", parent: "public.image"),
        "public.tiff": .init(mime: "image/tiff", parent: "public.image")
    ]

    private init(known: String) { identifier = known }
    public init?(_ identifier: String) {
        let key = identifier.lowercased()
        guard Self.declarations[key] != nil else { return nil }
        self.init(known: key)
    }

    public init?(mimeType: String, conformingTo supertype: UTType = .data) {
        let mime = mimeType.lowercased().replacingOccurrences(of: " ", with: "")
        let base = String(mime.prefix { $0 != ";" })
        guard let match = Self.declarations.first(where: { $0.value.mime == mime })
                ?? Self.declarations.first(where: { $0.value.mime == base }) else { return nil }
        self.init(known: match.key)
        if !conforms(to: supertype) { return nil }
    }

    public var preferredMIMEType: String? { Self.declarations[identifier]?.mime }
    public func conforms(to other: UTType) -> Bool {
        var current: String? = identifier
        while let value = current {
            if value == other.identifier { return true }
            // Text and images are both byte data and document content.
            if other == .content && (value == "public.text" || value == "public.image") { return true }
            current = Self.declarations[value]?.parent
        }
        return false
    }

    public static let item = Self(known: "public.item"), content = Self(known: "public.content"), data = Self(known: "public.data")
    public static let text = Self(known: "public.text"), plainText = Self(known: "public.plain-text"), utf8PlainText = Self(known: "public.utf8-plain-text")
    public static let html = Self(known: "public.html"), url = Self(known: "public.url"), fileURL = Self(known: "public.file-url")
    public static let image = Self(known: "public.image"), png = Self(known: "public.png"), jpeg = Self(known: "public.jpeg")
    public static let gif = Self(known: "com.compuserve.gif"), webP = Self(known: "org.webmproject.webp")
    public static let heic = Self(known: "public.heic"), heif = Self(known: "public.heif"), bmp = Self(known: "com.microsoft.bmp")
    public static let ico = Self(known: "com.microsoft.ico"), tiff = Self(known: "public.tiff")
}
