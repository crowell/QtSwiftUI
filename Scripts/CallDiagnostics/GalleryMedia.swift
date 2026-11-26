import SwiftUI
import CoreFoundation
import ImageBMP
import ImagePNG
import SignalI18n

extension PixelImage {
    @ViewBuilder var raster: some View {
        let data = image.pixels.withUnsafeBytes {
            CFDataCreate(nil, $0.bindMemory(to: UInt8.self).baseAddress, $0.count)
        }
        if let data, let provider = CGDataProvider(data: data), let space = CGColorSpace(name: CGColorSpace.sRGB),
           let cgImage = CGImage(width: image.width, height: image.height, bitsPerComponent: 8, bitsPerPixel: 32,
                                 bytesPerRow: image.width * 4, space: space,
                                 bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                                 provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) {
            Image(decorative: cgImage, scale: image.scale).resizable()
        }
    }
}

enum GalleryMediaSample {
    static let attachments: [MessageAttachment] = AttachmentSectionFixtures.media.map { src, sizeText, state in
        let parts = sizeText.split(separator: " ")
        let size = parts.first.flatMap { Double($0) }.map { Int(($0 * 1_000_000).rounded()) } ?? 1000
        var attachment = MessageAttachment(contentType: "image/png", size: size)
        attachment.hasUrl = state == 0
        attachment.pending = state == 2
        if src.hasPrefix("/fixtures/"),
           let dir = Bundle.module.url(forResource: "Media", withExtension: nil),
           let data = try? Data(contentsOf: dir.appendingPathComponent(String(src.dropFirst("/fixtures/".count)))),
           let decoded = try? PNGDecoder.decode([UInt8](data)) {
            attachment.image = RGBAImage(decoded.stillImage)
        } else if let comma = src.firstIndex(of: ","), let data = Data(base64Encoded: String(src[src.index(after: comma)...])),
                  let decoded = try? BMPDecoder.decode([UInt8](data)) {
            attachment.blurHash = RGBAImage(decoded)
        }
        return attachment
    }
}

/// The attachment-section media story mounted below the production gallery controls.
struct GalleryMediaSection: View {
    let attachments: [MessageAttachment]
    let order: MediaSortOrder
    let onClick: (Int) -> Void
    @Environment(\.i18n) private var i18n

    var body: some View {
        let indices = order == .date ? Array(attachments.indices) : attachments.indices.sorted { attachments[$0].size > attachments[$1].size }
        AttachmentSection(header: order == .date ? i18n("icu:today") : nil, kind: .media) {
            ForEach(indices, id: \.self) { index in
                MediaGridItem(attachment: attachments[index], showSize: order == .size) { onClick(index) }
            }
        }
        .frame(minWidth: 360, maxWidth: 660)
    }
}
