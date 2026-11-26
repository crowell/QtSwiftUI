import SwiftUI
import ImagePNG

struct ScreenSharePreview: View {
    @Environment(\.dismiss) private var dismiss
    var onSelect: ((String) -> Void)?
    var onCancel: (() -> Void)?

    static func pngFixture(_ filename: String) -> RGBAImage? {
        guard let directory = Bundle.module.url(forResource: "Media", withExtension: nil),
              let data = try? Data(contentsOf: directory.appendingPathComponent(filename)),
              let decoded = try? PNGDecoder.decode([UInt8](data)) else { return nil }
        return RGBAImage(decoded.stillImage)
    }

    var body: some View {
        AxoBaseDialog.Host {
            CallingSelectPresentingSourcesModal(sources: Self.sources, onSourceSelect: { id in
                if let onSelect { onSelect(id) } else { dismiss() }
            }, onCancel: {
                if let onCancel { onCancel() } else { dismiss() }
            })
        }
        .background(AxoColor.surfacePrimary)
    }
}
