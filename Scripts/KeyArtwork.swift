import SwiftUI

struct KeyArtwork: View {
    var body: some View {
        HStack(spacing: 0) {
            tile(.light, background: .white)
            tile(.dark, background: Color(.sRGB, red: 0.13, green: 0.13, blue: 0.13))
        }
    }

    private func tile(_ scheme: ColorScheme, background: Color) -> some View {
        KeyTransparencyIllustration()
            .environment(\.colorScheme, scheme)
            .frame(width: 158, height: 158)
            .background(background)
    }
}
