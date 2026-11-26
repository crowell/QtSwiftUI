import SwiftUI
import ImageJPEG

@MainActor @Observable final class PhotoPreviewModel {
    let media: [LightboxMediaItem]
    var selected: Int
    var action: String?

    init(media: [LightboxMediaItem] = PhotoPreviewModel.sample, selected: Int = 0) {
        self.media = media
        self.selected = selected
    }

    static let sample: [LightboxMediaItem] = {
        var items: [LightboxMediaItem] = []
        if let directory = Bundle.module.url(forResource: "Media", withExtension: nil),
           let data = try? Data(contentsOf: directory.appendingPathComponent("tina-rolf-269345-unsplash.jpg")),
           let decoded = try? JPEGDecoder.decode([UInt8](data)) {
            let photo = RGBAImage(decoded)
            items.append(.init(kind: .image, image: photo, thumbnail: photo, caption: "Lighthouse on the coast · Tina Rolf"))
        }
        if let cat = GalleryMediaSample.attachments.compactMap(\.image).first {
            items.append(.init(kind: .image, image: cat, thumbnail: cat, caption: "Photo from the media gallery"))
        }
        return items
    }()
}

struct PhotoPreview: View {
    @State var model = PhotoPreviewModel()
    var close: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    @Environment(\.i18n) private var i18n

    var body: some View {
        Lightbox(media: model.media, selectedIndex: model.selected,
                 header: .init(title: "Alice", color: "A180", timestamp: "10:45 AM"),
                 closeLightbox: { if let close { close() } else { dismiss() } },
                 onForward: { model.action = i18n("icu:forwardMessage") },
                 onSave: { model.action = i18n("icu:save") },
                 onPrevAttachment: { model.selected = max(0, model.selected - 1) },
                 onNextAttachment: { model.selected = min(model.media.count - 1, model.selected + 1) },
                 onSelectAttachment: { model.selected = $0 })
            .overlay {
                if let action = model.action {
                    AxoBaseDialog.Host {
                        AxoConfirmDialog.Root(title: action, description: "Local photo preview") {
                            AxoConfirmDialog.Action(i18n("icu:ok"), variant: .strongPrimary) { model.action = nil }
                        }
                    }
                }
            }
    }
}
