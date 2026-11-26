import Foundation

/// A uniform type identifier and its MIME representation at the Qt desktop boundary.
public struct UTType: Hashable, Codable, Sendable {
    public let identifier: String
    private struct Declaration {
        let mime: String?
        let parent: String?
        var extensions: [String] = []
    }

    private static let declarations: [String: Declaration] = [
        "public.item": .init(mime: nil, parent: nil),
        "public.directory": .init(mime: "inode/directory", parent: "public.item"),
        "public.folder": .init(mime: nil, parent: "public.directory"),
        "public.content": .init(mime: nil, parent: "public.item"),
        "public.data": .init(mime: "application/octet-stream", parent: "public.item"),
        "public.text": .init(mime: nil, parent: "public.data"),
        "public.plain-text": .init(mime: "text/plain", parent: "public.text", extensions: ["txt","text"]),
        "public.utf8-plain-text": .init(mime: "text/plain;charset=utf-8", parent: "public.plain-text"),
        "public.html": .init(mime: "text/html", parent: "public.text", extensions: ["html","htm"]),
        "com.adobe.pdf": .init(mime: "application/pdf", parent: "public.data", extensions: ["pdf"]),
        "public.audiovisual-content": .init(mime: nil, parent: "public.data"),
        "public.movie": .init(mime: nil, parent: "public.audiovisual-content"),
        "public.video": .init(mime: nil, parent: "public.movie"),
        "public.audio": .init(mime: nil, parent: "public.audiovisual-content"),
        "public.mpeg-4": .init(mime: "video/mp4", parent: "public.movie", extensions: ["mp4"]),
        "public.mpeg": .init(mime: "video/mpeg", parent: "public.movie", extensions: ["mpg","mpeg"]),
        "com.apple.quicktime-movie": .init(mime: "video/quicktime", parent: "public.movie", extensions: ["mov","qt"]),
        "org.webmproject.webm": .init(mime: "video/webm", parent: "public.movie", extensions: ["webm"]),
        "com.apple.m4v-video": .init(mime: "video/x-m4v", parent: "public.mpeg-4", extensions: ["m4v"]),
        "public.avi": .init(mime: "video/avi", parent: "public.movie", extensions: ["avi"]),
        "org.matroska.mkv": .init(mime: nil, parent: "public.movie", extensions: ["mkv"]),
        "public.mp3": .init(mime: "audio/mpeg", parent: "public.audio", extensions: ["mp3"]),
        "public.mpeg-4-audio": .init(mime: "audio/mp4", parent: "public.audio", extensions: ["mp4"]),
        "com.apple.m4a-audio": .init(mime: "audio/x-m4a", parent: "public.mpeg-4-audio", extensions: ["m4a"]),
        "com.microsoft.waveform-audio": .init(mime: "audio/vnd.wave", parent: "public.audio", extensions: ["wav"]),
        "org.xiph.ogg-audio": .init(mime: "audio/ogg", parent: "public.audio", extensions: ["ogg","oga","opus"]),
        "org.xiph.flac": .init(mime: "audio/flac", parent: "public.audio", extensions: ["flac"]),
        "public.aac-audio": .init(mime: "audio/aac", parent: "public.audio", extensions: ["aac"]),
        "public.url": .init(mime: "text/uri-list", parent: "public.data"),
        "public.file-url": .init(mime: nil, parent: "public.url"),
        "public.image": .init(mime: nil, parent: "public.data"),
        "public.png": .init(mime: "image/png", parent: "public.image", extensions: ["png"]),
        "public.jpeg": .init(mime: "image/jpeg", parent: "public.image", extensions: ["jpeg","jpg","jpe"]),
        "com.compuserve.gif": .init(mime: "image/gif", parent: "public.image", extensions: ["gif"]),
        "org.webmproject.webp": .init(mime: "image/webp", parent: "public.image", extensions: ["webp"]),
        "public.avif": .init(mime: "image/avif", parent: "public.image", extensions: ["avif"]),
        "public.heic": .init(mime: "image/heic", parent: "public.image", extensions: ["heic"]),
        "public.heif": .init(mime: "image/heif", parent: "public.image", extensions: ["heif"]),
        "com.microsoft.bmp": .init(mime: "image/bmp", parent: "public.image", extensions: ["bmp"]),
        "com.microsoft.ico": .init(mime: "image/vnd.microsoft.icon", parent: "public.image", extensions: ["ico"]),
        "public.tiff": .init(mime: "image/tiff", parent: "public.image", extensions: ["tiff","tif"])
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

    public init?(filenameExtension: String, conformingTo supertype: UTType = .data) {
        let ext = filenameExtension.lowercased()
        let candidates = Self.declarations.filter { $0.value.extensions.contains(ext) }
        // The movie and audio MPEG-4 types share the mp4 extension.
        if ext == "mp4", Self.mpeg4Movie.conforms(to: supertype) { self = .mpeg4Movie; return }
        guard let key = candidates.keys.sorted().first(where: { Self(known: $0).conforms(to: supertype) }) else { return nil }
        self.init(known: key)
    }

    public var preferredFilenameExtension: String? { Self.declarations[identifier]?.extensions.first }
    public var preferredMIMEType: String? { Self.declarations[identifier]?.mime }
    public func conforms(to other: UTType) -> Bool {
        var current: String? = identifier
        while let value = current {
            if value == other.identifier { return true }
            // Text and images are both byte data and document content.
            if other == .content && ["public.text", "public.image", "public.audiovisual-content", "com.adobe.pdf"].contains(value) { return true }
            current = Self.declarations[value]?.parent
        }
        return false
    }

    public static let item = Self(known: "public.item"), content = Self(known: "public.content"), data = Self(known: "public.data")
    public static let directory = Self(known: "public.directory"), folder = Self(known: "public.folder")
    public static let text = Self(known: "public.text"), plainText = Self(known: "public.plain-text"), utf8PlainText = Self(known: "public.utf8-plain-text")
    public static let html = Self(known: "public.html"), url = Self(known: "public.url"), fileURL = Self(known: "public.file-url")
    public static let pdf = Self(known: "com.adobe.pdf")
    public static let audiovisualContent = Self(known: "public.audiovisual-content")
    public static let movie = Self(known: "public.movie"), video = Self(known: "public.video"), audio = Self(known: "public.audio")
    public static let mpeg4Movie = Self(known: "public.mpeg-4"), quickTimeMovie = Self(known: "com.apple.quicktime-movie")
    public static let mp3 = Self(known: "public.mp3"), wav = Self(known: "com.microsoft.waveform-audio"), mpeg4Audio = Self(known: "public.mpeg-4-audio")
    public static let image = Self(known: "public.image"), png = Self(known: "public.png"), jpeg = Self(known: "public.jpeg")
    public static let gif = Self(known: "com.compuserve.gif"), webP = Self(known: "org.webmproject.webp")
    public static let heic = Self(known: "public.heic"), heif = Self(known: "public.heif"), bmp = Self(known: "com.microsoft.bmp")
    public static let ico = Self(known: "com.microsoft.ico"), tiff = Self(known: "public.tiff")
}
