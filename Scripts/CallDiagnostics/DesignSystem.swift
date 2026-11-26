import Foundation
import SwiftUI
#if os(Linux)
import QtBridge
@_spi(Qt) import SwiftUI
extension View {
    func caSpin(period: Double) -> some View { qtContinuousRotation(period: period) }
}
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
    static func interName(weight: Int) -> String {
        weight >= 600 ? "Inter-SemiBold" : weight >= 500 ? "Inter-Medium" : "Inter-Regular"
    }
    static func inter(size: CGFloat, weight: Int) -> Font {
        let weight: Font.Weight = weight >= 600 ? .semibold : weight >= 500 ? .medium : .regular
        return Font.custom("Inter", fixedSize: size).weight(weight)
    }
}

extension View {
    func cssTextColor(_ color: AxoColor) -> some View { environment(\.cssTextColor, color).foregroundStyle(color) }
}

public struct CSSTextRun {
    let text: String
    public init(_ text: String) { self.text = text }
}
public struct CSSTextStyle {
    var fontName: String
    var size: CGFloat
    var lineHeight: CGFloat
    var letterSpacing: CGFloat

    init(_ type: AxoType) {
        self.init(fontName: AxoFonts.interName(weight: type.weight), size: type.size,
                  lineHeight: type.lineHeight, letterSpacing: type.tracking * type.size)
    }
    init(fontName: String, size: CGFloat, lineHeight: CGFloat, letterSpacing: CGFloat) {
        self.fontName = fontName
        self.size = size
        self.lineHeight = lineHeight
        self.letterSpacing = letterSpacing
    }
    var type: AxoType {
        let weight = fontName == "Inter-SemiBold" ? 600 : fontName == "Inter-Medium" ? 500 : 400
        return AxoType(size: size, lineHeight: lineHeight, weight: weight, tracking: size > 0 ? letterSpacing / size : 0)
    }
}
extension EnvironmentValues {
    @Entry var titleBarDragAreaHeight: CGFloat = 0
    @Entry var cssTextColor: AxoColor = .labelPrimary
    @Entry var cssTextWrapWidth: CGFloat? = nil
    @Entry var axoInheritedTextSize: (size: CGFloat, lineHeight: CGFloat) = (14, 20)
}
enum PreviewWrap { case wrap, truncate, nowrap }
extension TextAlignment {
    static var end: Self { .trailing }
}

struct CSSText: View {
    let value: String
    let type: AxoType
    let wrap: PreviewWrap
    let alignment: TextAlignment
    let color: AxoColor?
    @Environment(\.cssTextWrapWidth) private var wrapWidth

    init(_ value: String, type: AxoType, wrap: PreviewWrap = .wrap, alignment: TextAlignment = .leading, color: AxoColor? = nil) {
        self.value = value
        self.type = type
        self.wrap = wrap
        self.alignment = alignment
        self.color = color
    }
    init(_ value: String, style: CSSTextStyle, wrap: PreviewWrap = .wrap, alignment: TextAlignment = .leading, color: AxoColor? = nil) {
        self.init(value, type: style.type, wrap: wrap, alignment: alignment, color: color)
    }
    init(runs: [CSSTextRun], style: CSSTextStyle, wrap: PreviewWrap, color: AxoColor? = nil) {
        self.init(runs.map(\.text).joined(), type: style.type, wrap: wrap, color: color)
    }
    init(runs: [CSSTextRun], style: CSSTextStyle, onTap: ((String) -> Void)?) {
        // This preview only supplies plain localized strings to the production dialog.
        self.init(runs: runs, style: style, wrap: .wrap)
    }
    @ViewBuilder private var label: some View {
        let _ = AxoFonts.register()
        let text = Text(verbatim: value).font(type.font).tracking(type.tracking * type.size)
        if wrap == .nowrap {
            text.lineLimit(1).fixedSize(horizontal: true, vertical: false).frame(height: type.lineHeight)
        } else if wrap == .truncate {
            text.lineLimit(1).frame(height: type.lineHeight)
        } else {
            text.fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: wrapWidth, minHeight: type.lineHeight, alignment: .leading)
        }
    }
    var body: some View {
        Group {
            if let color { label.foregroundStyle(color) } else { label }
        }.multilineTextAlignment(alignment)
    }
}
public enum AxoSymbol {
    public typealias Name = String
    struct Icon: View {
        let symbol: Name
        let size: CGFloat
        let label: String?
        @Environment(\.layoutDirection) var direction
        init(_ symbol: Name, size: CGFloat, label: String?) {
            self.symbol = symbol
            self.size = size
            self.label = label
        }
        var body: some View {
            let _ = AxoFonts.register()
            Text(verbatim: String(AxoSymbol.icon(symbol, rtl: direction == .rightToLeft)))
                .font(.custom("Signal Symbols", fixedSize: size))
                .frame(width: size, height: size)
                .accessibilityLabel(label ?? "").accessibilityHidden(label == nil)
        }
    }
    struct InlineGlyph: View {
        @Environment(\.layoutDirection) var direction
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
            Text(verbatim: String(AxoSymbol.inlineGlyph(symbol, rtl: direction == .rightToLeft)))
                .font(.custom("Signal Symbols", fixedSize: size).weight(weight >= 600 ? .semibold : .regular))
                .frame(height: size).accessibilityHidden(true)
        }
    }
}
