import SwiftUI
import ImageJPEG

@MainActor enum StickerSamples {
    static func fixtureImage(_ name: String) -> RGBAImage? {
        if let directory = Bundle.module.url(forResource: "Media", withExtension: nil),
           let data = try? Data(contentsOf: directory.appendingPathComponent(name)),
           let image = try? JPEGDecoder.decode([UInt8](data)) {
            return RGBAImage(image)
        }
        return GalleryMediaSample.attachments.compactMap(\.image).first
    }
}

@MainActor @Observable final class StickerPreviewModel {
    var packs: [StickerPack]
    var selectedID: String?

    init() {
        let stickers = (1...3).map { Sticker(id: $0, emoji: "🐱", image: StickerSamples.fixtureImage("kitten-\($0)-64-64.jpg")) }
        packs = (StickerSamples.blessed + StickerSamples.received).map { pack in
            var result = pack
            result.stickers = stickers
            result.stickerCount = stickers.count
            return result
        }
    }

    func setStatus(_ id: String, _ status: StickerPack.Status) {
        guard let index = packs.firstIndex(where: { $0.id == id }) else { return }
        packs[index].status = status
    }
}

struct StickerPreview: View {
    @State var model = StickerPreviewModel()

    var body: some View {
        StickerManager(blessedPacks: model.packs.filter(\.isBlessed), receivedPacks: model.packs.filter { !$0.isBlessed },
                       installedPacks: model.packs.filter { $0.status == .installed },
                       onClickPreview: { model.selectedID = $0 },
                       install: { model.setStatus($0.id, .installed) }, uninstall: { model.setStatus($0.id, .downloaded) })
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AxoColor.surfacePrimary)
            .overlay {
                if let selected = model.packs.first(where: { $0.id == model.selectedID }) {
                    AxoBaseDialog.Host {
                        StickerPreviewModal(pack: selected, closeStickerPackPreview: { model.selectedID = nil },
                                           installStickerPack: { id, _ in model.setStatus(id, .installed) },
                                           uninstallStickerPack: { id, _ in model.setStatus(id, .downloaded) })
                    }
                }
            }
            .axoModalHost()
    }
}
