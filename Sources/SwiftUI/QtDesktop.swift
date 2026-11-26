import QtBridge
import Glibc

@_spi(Qt) @MainActor public enum QtDesktop {
    public static var keyboardModifiers: EventModifiers { EventModifiers(rawValue: Int(qs_keyboard_modifiers())) }
    public static var keyboardFocusVisible: Bool { qs_keyboard_focus_visible() != 0 }

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

    public static var isActive: Bool { qs_application_active() != 0 }
    public static func requestAttention() { qs_request_attention() }
    public static func setAppearance(_ scheme: ColorScheme?) {
        qs_application_appearance(scheme == .dark ? 2 : scheme == .light ? 1 : 0)
    }

    public static func saveFile(named name: String, directory: URL? = nil, types: [UTType] = []) -> URL? {
        let filename = directory?.appendingPathComponent(name).path ?? name
        let patterns = types.compactMap(\.preferredFilenameExtension).map { "*.\($0)" }.joined(separator: " ")
        guard let result = qs_choose_save_path(filename, patterns.isEmpty ? "" : "Files (\(patterns))") else { return nil }
        defer { free(result) }
        return URL(fileURLWithPath: String(cString: result))
    }

    public static func chooseFiles(types: [UTType] = [], directory: URL? = nil, folders: Bool = false,
                                   multiple: Bool = false, prompt: String? = nil) -> [URL] {
        let mime = types.map { type in
            if type == .image { return "image/*" }
            if type == .movie { return "video/*" }
            return type.preferredMIMEType ?? "*"
        }.joined(separator: "\n")
        guard let result = qs_choose_files(mime, folders ? 1 : 0, multiple ? 1 : 0, directory?.path, prompt) else { return [] }
        defer { free(result) }
        return String(cString: result).split(separator: "\n").compactMap { URL(string: String($0)) }
    }

    public static func copy(_ text: String) { qs_clipboard_text(text) }
}
