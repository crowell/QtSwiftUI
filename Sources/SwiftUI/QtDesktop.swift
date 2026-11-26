import QtBridge

@_spi(Qt) @MainActor public enum QtDesktop {
    public static var primaryScreenSize: CGSize? {
        let size = qs_primary_screen_size()
        guard size.width > 0, size.height > 0 else { return nil }
        return CGSize(width: size.width, height: size.height)
    }

    public static func icon(named name: String, size: Int) -> Image? {
        guard (1...1024).contains(size) else { return nil }
        final class Result { var bytes: Data? }
        let result = Result()
        let success = qs_theme_icon(name, Int32(size), Unmanaged.passUnretained(result).toOpaque()) { object, bytes, count, _ in
            guard let object, let bytes else { return }
            Unmanaged<Result>.fromOpaque(object).takeUnretainedValue().bytes = Data(bytes: bytes, count: count)
        }
        guard success != 0, let pixels = result.bytes else { return nil }
        return Image(rgba8: pixels, width: size, height: size)
    }

    public static func copy(_ text: String) { qs_clipboard_text(text) }
}
