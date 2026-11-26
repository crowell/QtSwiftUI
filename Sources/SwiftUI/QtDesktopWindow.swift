import QtBridge

/// Hosts a SwiftUI view in an independent Qt top-level window.
@_spi(Qt) @MainActor public final class QtDesktopWindow {
    private var host: Host?
    private let onClose: () -> Void

    public init<Content: View>(title: String, size: CGSize, onClose: @escaping () -> Void = {},
                               @ViewBuilder content: @escaping () -> Content) {
        let host = Host(title: title) { content().resolve($0) }
        self.host = host
        self.onClose = onClose
        host.observeClose { [weak self] in self?.close() }
        host.open(width: Int(size.width), height: Int(size.height))
    }

    public func activate() {
        if let host { qs_window_raise(host.window) }
    }

    public func close() {
        guard let host else { return }
        self.host = nil
        host.close()
        onClose()
    }

    isolated deinit { host?.close() }
}
