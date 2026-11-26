import QtBridge

@_spi(Qt) public enum QtFontDatabase {
    public static func registerFont(at url: URL) -> Bool {
        url.isFileURL && qs_register_font(url.path) != 0
    }

    public static func font(family: String, size: CGFloat, weight: Int) -> Font {
        Font.custom(family, fixedSize: size).weight(Font.Weight(value: Int32(clamping: min(1000, max(1, weight)))))
    }

    public static func inkSize(of text: String, family: String, size: CGFloat) -> CGSize {
        let ink = qs_text_ink(text, text.utf8.count, family, size)
        return CGSize(width: ink.width, height: ink.height)
    }

    public static func metrics(family: String, size: CGFloat) -> (ascent: CGFloat, descent: CGFloat, xHeight: CGFloat) {
        let metrics = qs_font_metrics(family, size)
        return (metrics.ascent, metrics.descent, metrics.xHeight)
    }
}
