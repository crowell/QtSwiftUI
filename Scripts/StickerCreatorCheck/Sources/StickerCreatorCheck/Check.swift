import Foundation
import MediaXPCInterface
import SignalI18n
import SignalUI
import SwiftUI

@main struct StickerCreatorCheck: SwiftUI.App {
    private let i18n = Localizer(locale: "en")
    private let model: StickerCreatorModel

    init() {
        AxoFonts.register()
        let media = MediaXPCClient()
        model = StickerCreatorModel(process: { bytes in
            guard let image = try? await media.stickerImage(bytes) else {
                return .refused("StickerCreator--Toasts--errorProcessing")
            }
            if let refusal = image.refusal { return .refused(refusal.rawValue) }
            FileHandle.standardOutput.write(Data("Decoded sticker \(image.previewWidth)x\(image.previewHeight)\n".utf8))
            return .sticker(data: image.data, contentType: image.contentType,
                            preview: RGBAImage(width: image.previewWidth, height: image.previewHeight,
                                               pixels: image.previewRGBA, scale: 2))
        }, upload: { _, _, _, _, _ in throw URLError(.userAuthenticationRequired) })
    }

    var body: some Scene {
        WindowGroup(i18n("ArtCreator--title")) {
            StickerCreator(model: model).environment(\.i18n, i18n).axoModalHost().axoViewport()
        }
        .defaultSize(width: 800, height: 650)
    }
}
