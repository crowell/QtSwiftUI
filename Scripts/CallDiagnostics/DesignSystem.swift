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
    static func width(_ text: String, style: CSSTextStyle) -> CGFloat {
        register()
        #if os(Linux)
        return qs_text_width(text, style.fontName, style.size, style.letterSpacing)
        #else
        let font = CTFontCreateWithName(style.fontName as CFString, style.size, nil)
        let string = NSAttributedString(string: text, attributes: [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTKernAttributeName as String): style.letterSpacing,
        ])
        return CGFloat(CTLineGetTypographicBounds(CTLineCreateWithAttributedString(string), nil, nil, nil))
        #endif
    }
    static func interMetrics(size: CGFloat) -> (ascent: CGFloat, descent: CGFloat, xHeight: CGFloat) {
        metrics(family: "Inter", size: size)
    }
    static func metrics(family: String, size: CGFloat) -> (ascent: CGFloat, descent: CGFloat, xHeight: CGFloat) {
        register()
        #if os(Linux)
        let font = qs_font_metrics(family, size)
        return (font.ascent, font.descent, font.xHeight)
        #else
        let font = CTFontCreateWithName(family as CFString, size, nil)
        return (CTFontGetAscent(font), CTFontGetDescent(font), CTFontGetXHeight(font))
        #endif
    }
    static func interName(weight: Int) -> String {
        weight >= 600 ? "Inter-SemiBold" : weight >= 500 ? "Inter-Medium" : "Inter-Regular"
    }
    static func inter(size: CGFloat, weight: Int = 400) -> Font {
        let weight: Font.Weight = weight >= 600 ? .semibold : weight >= 500 ? .medium : .regular
        return Font.custom("Inter", fixedSize: size).weight(weight)
    }
}

extension View {
    func cssTextColor(_ color: AxoColor) -> some View { environment(\.cssTextColor, color).foregroundStyle(color) }
}

public struct CSSTextRun: Hashable, Sendable {
    public var text: String
    public var fontName: String?
    public var color: AxoColor?
    public var action: String?
    public var background: AxoColor?
    public var underline = false
    public var emojify = false
    public var emojiSize: CGFloat?
    public var emojiTopMargin: CGFloat?
    public var breakAll = false
    public init(_ text: String, fontName: String? = nil, color: AxoColor? = nil, action: String? = nil) {
        self.text = text
        self.fontName = fontName
        self.color = color
        self.action = action
    }
}
public struct CSSTextStyle {
    var fontName: String
    var size: CGFloat
    var lineHeight: CGFloat
    var letterSpacing: CGFloat
    var tabular = false

    func tabularNums() -> Self {
        var copy = self
        copy.tabular = true
        return copy
    }

    public init(_ type: AxoType) {
        self.init(fontName: AxoFonts.interName(weight: type.weight), size: type.size,
                  lineHeight: type.lineHeight, letterSpacing: type.tracking * type.size)
    }
    init(fontName: String, size: CGFloat, lineHeight: CGFloat, letterSpacing: CGFloat = 0) {
        self.fontName = fontName
        self.size = size
        self.lineHeight = lineHeight
        self.letterSpacing = letterSpacing
    }
    #if canImport(CoreText)
    var ctFont: CTFont {
        AxoFonts.register()
        return CTFontCreateWithName(fontName as CFString, size, nil)
    }
    #endif
    var fontMetrics: (ascent: CGFloat, descent: CGFloat, xHeight: CGFloat) { AxoFonts.metrics(family: fontName, size: size) }
    var weight: Int {
        if fontName.hasSuffix("SemiBold") { return 600 }
        if fontName.hasSuffix("Bold") { return 700 }
        if fontName.hasSuffix("Medium") { return 500 }
        return 400
    }
    var type: AxoType {
        return AxoType(size: size, lineHeight: lineHeight, weight: weight, tracking: size > 0 ? letterSpacing / size : 0)
    }
}
extension EnvironmentValues {
    @Entry var cssTextColor: AxoColor = .labelPrimary
    @Entry var cssTextWrapWidth: CGFloat? = nil
}
public enum CSSTextWrap: Equatable { case wrap, truncate, nowrap, balance, clamp(Int) }
extension TextAlignment {
    static var start: Self { .leading }
    static var end: Self { .trailing }
}

// Narrow the text column until another wrap would add a line.
private struct BalancedTextLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let text = subviews.first else { return .zero }
        let size = text.sizeThatFits(proposal)
        guard let width = proposal.width, width.isFinite, width > 1,
              size.height > text.sizeThatFits(.unspecified).height else { return size }
        var low: CGFloat = 1
        var high = min(width, ceil(size.width))
        while high - low > 1 {
            let middle = floor((low + high) / 2)
            if text.sizeThatFits(.init(width: middle, height: nil)).height <= size.height { high = middle }
            else { low = middle }
        }
        return CGSize(width: high, height: size.height)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: .init(width: bounds.width, height: bounds.height))
    }
}

public struct CSSText: View {
    let value: String
    let type: AxoType
    let wrap: CSSTextWrap
    let alignment: TextAlignment
    let color: AxoColor?
    private var runs: [CSSTextRun] = []
    private var tabular = false
    private var onTap: ((String) -> Void)?
    @Environment(\.colorScheme) private var scheme
    @Environment(\.cssTextWrapWidth) private var wrapWidth

    init(_ value: String, type: AxoType, wrap: CSSTextWrap = .wrap, alignment: TextAlignment = .leading, color: AxoColor? = nil) {
        self.value = value
        self.type = type
        self.wrap = wrap
        self.alignment = alignment
        self.color = color
    }
    init(_ value: String, style: CSSTextStyle, wrap: CSSTextWrap = .wrap, alignment: TextAlignment = .leading, color: AxoColor? = nil) {
        self.init(value, type: style.type, wrap: wrap, alignment: alignment, color: color)
        self.tabular = style.tabular
    }
    init(runs: [CSSTextRun], style: CSSTextStyle, wrap: CSSTextWrap = .wrap, alignment: TextAlignment = .leading, color: AxoColor? = nil,
         onTap: ((String) -> Void)? = nil) {
        let displayed = runs.map { run -> CSSTextRun in
            guard run.breakAll else { return run }
            var copy = run
            copy.text = run.text.map(String.init).joined(separator: "\u{200B}")
            return copy
        }
        self.init(displayed.map(\.text).joined(), type: style.type, wrap: wrap, alignment: alignment, color: color)
        self.tabular = style.tabular
        if runs.contains(where: { $0.action != nil || $0.color != nil || $0.background != nil || $0.fontName != nil || $0.underline || ($0.emojify && $0.text.contains(where: CSSTextLayout.isEmoji)) }) { self.runs = displayed }
        self.onTap = onTap
    }
    private var content: Text {
        guard !runs.isEmpty else { return Text(verbatim: value) }
        var attributed = AttributedString()
        for run in runs {
            var part = AttributedString(run.text)
            if let name = run.fontName { part.font = Font.custom(name, fixedSize: type.size) }
            if let color = run.color { part.foregroundColor = color.value(for: scheme).color }
            if let background = run.background { part.backgroundColor = background.value(for: scheme).color }
            if let action = run.action {
                var url = URLComponents()
                url.scheme = "serein"
                url.host = "text-action"
                url.queryItems = [URLQueryItem(name: "action", value: action)]
                part.link = url.url
            }
            if run.underline { part.underlineStyle = .single }
            if run.emojify {
                let size = run.emojiSize ?? (type.size * 1.4).rounded()
                var index = part.startIndex
                for ch in run.text {
                    let end = part.characters.index(after: index)
                    if CSSTextLayout.isEmoji(ch) { part[index..<end].font = .custom("SignalEmojiLarge", fixedSize: size) }
                    index = end
                }
            }
            attributed += part
        }
        return Text(attributed)
    }
    @ViewBuilder private var label: some View {
        let _ = AxoFonts.register()
        let text = content.font(type.font).tracking(type.tracking * type.size)
        if tabular && wrap == .nowrap && !value.isEmpty && value.allSatisfy({ $0.isASCII && $0.isNumber }) {
            HStack(spacing: 0) {
                ForEach(Array(value.enumerated()), id: \.offset) { _, digit in
                    ZStack {
                        ForEach(0..<10) { Text(verbatim: String($0)).hidden() }
                        Text(verbatim: String(digit))
                    }
                }
            }.font(type.font).tracking(type.tracking * type.size)
                .fixedSize(horizontal: true, vertical: false).frame(height: type.lineHeight)
                .accessibilityElement(children: .ignore).accessibilityLabel(value)
        } else if wrap == .balance {
            BalancedTextLayout { text.fixedSize(horizontal: false, vertical: true) }
                .frame(minHeight: type.lineHeight)
        } else if wrap == .nowrap {
            text.lineLimit(1).fixedSize(horizontal: true, vertical: false).frame(height: type.lineHeight)
        } else if case .clamp(let lines) = wrap {
            text.lineLimit(lines).fixedSize(horizontal: false, vertical: true).frame(minHeight: type.lineHeight)
        } else if wrap == .truncate {
            text.lineLimit(1).frame(height: type.lineHeight)
        } else {
            text.fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: wrapWidth, minHeight: type.lineHeight, alignment: .leading)
        }
    }
    public var body: some View {
        Group {
            if let color { label.foregroundStyle(color) } else { label }
        }.multilineTextAlignment(alignment)
        .environment(\.openURL, OpenURLAction { url in
            guard url.scheme == "serein", url.host == "text-action", let onTap,
                  let action = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "action" })?.value
            else { return .systemAction }
            onTap(action)
            return .handled
        })
    }
}
public enum AxoSymbol {
    static func style(size: CGFloat, weight: Int) -> CSSTextStyle {
        CSSTextStyle(fontName: "Signal Symbols", size: size, lineHeight: size)
    }
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
