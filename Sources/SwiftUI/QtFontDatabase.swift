import QtBridge

@_spi(Qt) public enum QtFontDatabase {
    public static func registerFont(at url: URL) -> Bool {
        url.isFileURL && qs_register_font(url.path) != 0
    }

    public static func metrics(family: String, size: CGFloat) -> (ascent: CGFloat, descent: CGFloat, xHeight: CGFloat) {
        let metrics = qs_font_metrics(family, size)
        return (metrics.ascent, metrics.descent, metrics.xHeight)
    }
}
