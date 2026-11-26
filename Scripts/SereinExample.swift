import SwiftUI

private struct DeviceCard: View {
    @State private var theme: ThemeSetting = .light
    private let tint = AxoColor(light: RGBA(hex: 0x293D78), dark: RGBA(hex: 0xCCD7FF))
    private let surface = AxoColor(light: RGBA(hex: 0xF2F4FA), dark: RGBA(hex: 0x252B36))
    private let panel = AxoColor(light: RGBA(hex: 0xFFFFFF), dark: RGBA(hex: 0x181B23))
    var body: some View {
        AxoTheme(theme) {
            AxoContainer.Root {
                VStack(alignment: .leading, spacing: 18) {
                    CSSFlex(.row, gap: 12, justify: .spaceBetween, align: .center) {
                        Text("Linked devices").font(.title.bold())
                        Button(theme == .light ? "Dark theme" : "Light theme") {
                            theme = theme == .light ? .dark : .light
                        }
                    }
                    CSSFlex(.row, gap: 22, align: .center) {
                        QrCode(text: "qtswiftui:device-preview", alt: "Preview device QR code")
                            .frame(width: 116, height: 116)
                            .padding(16)
                            .background(Color.white)
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Desktop preview").font(.title2.bold()).foregroundStyle(tint)
                            CSSGrid(columnGap: 14, rowGap: 8, stretchColumns: false) {
                                Text("System").foregroundStyle(.secondary).gridCell(row: 0, column: 0)
                                Text("Ubuntu Linux").gridCell(row: 0, column: 1)
                                Text("Toolkit").foregroundStyle(.secondary).gridCell(row: 1, column: 0)
                                Text("Qt Widgets").gridCell(row: 1, column: 1)
                            }
                        }
                        .flexItem(grow: 1, minMain: 0)
                    }
                    .padding(18)
                    .background(SuperellipseRect.curved(12).fill(surface))
                }
                .padding(12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Rectangle().fill(panel))
        }
    }
}
@main struct DevicePreview: App {
    var body: some Scene { WindowGroup("Serein components") { DeviceCard() }.defaultSize(width: 600, height: 274) }
}
