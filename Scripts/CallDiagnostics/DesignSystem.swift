import Foundation
import SwiftUI
#if os(Linux)
import QtBridge
#else
import CoreText
#endif

// The production screen and AxoButton use CoreText for their leaf labels.
// Render those labels with the same fonts, type scale and generated glyph map.
enum AxoFonts {
    private static let files: [URL] = {
        guard let folder = Bundle.module.url(forResource: "Fonts", withExtension: nil) else { return [] }
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "ttf" }
    }()
    #if os(Linux)
    static func register() {
        for file in files { _ = qs_register_font(file.path) }
    }
    #else
    private static let registered: Void = {
        for file in files { CTFontManagerRegisterFontsForURL(file as CFURL, .process, nil) }
    }()
    static func register() { _ = registered }
    #endif
    static func inter(size: CGFloat, weight: Int) -> Font {
        let weight: Font.Weight = weight >= 600 ? .semibold : weight >= 500 ? .medium : .regular
        return Font.custom("Inter", fixedSize: size).weight(weight)
    }
}

extension View {
    func cssTextColor(_ color: AxoColor) -> some View { foregroundStyle(color) }
}

public struct CSSTextRun {
    let text: String
    public init(_ text: String) { self.text = text }
}
struct CSSTextStyle {
    let type: AxoType
    init(_ type: AxoType) { self.type = type }
}
enum PreviewWrap { case wrap, truncate }

struct CSSText: View {
    let value: String
    let type: AxoType
    let wrap: PreviewWrap
    let color: AxoColor?

    init(_ value: String, type: AxoType, wrap: PreviewWrap = .wrap, color: AxoColor? = nil) {
        self.value = value
        self.type = type
        self.wrap = wrap
        self.color = color
    }
    init(runs: [CSSTextRun], style: CSSTextStyle, wrap: PreviewWrap) {
        self.init(runs.map(\.text).joined(), type: style.type, wrap: wrap)
    }
    var body: some View {
        let _ = AxoFonts.register()
        let text = Text(verbatim: value).font(type.font).tracking(type.tracking * type.size)
            .lineLimit(wrap == .truncate ? 1 : nil).frame(height: type.lineHeight)
        if let color { text.foregroundStyle(color) } else { text }
    }
}
public enum AxoSymbol {
    public typealias Name = String
    struct InlineGlyph: View {
        let symbol: String
        let size: CGFloat
        let weight: Int
        init(_ symbol: String, size: CGFloat, weight: Int) {
            self.symbol = symbol
            self.size = size
            self.weight = weight
        }
        var body: some View {
            let _ = AxoFonts.register()
            Text(verbatim: AxoSymbolDefs.base[symbol].map(String.init) ?? "")
                .font(.custom("Signal Symbols", fixedSize: size).weight(weight >= 600 ? .semibold : .regular))
                .frame(height: size).accessibilityHidden(true)
        }
    }
}
