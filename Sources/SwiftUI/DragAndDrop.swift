@_exported import UniformTypeIdentifiers
import QtBridge

/// The Linux item-provider implementation retains representations after the Qt drop event returns.
public final class NSItemProvider: NSObject {
    fileprivate struct Representation {
        let identifier: String
        let format: String
        let data: Data
    }
    fileprivate var representations: [Representation] = []
    public var registeredTypeIdentifiers: [String] { representations.map(\.identifier) }

    public override init() { super.init() }
    public init(object: NSString) {
        super.init()
        representations = [.init(identifier: UTType.utf8PlainText.identifier, format: "text/plain", data: Data((object as String).utf8))]
    }

    public init(object: NSURL) {
        super.init()
        let url = object as URL
        representations = [.init(identifier: (url.isFileURL ? UTType.fileURL : .url).identifier,
                                 format: "text/uri-list", data: Data((url.absoluteString + "\r\n").utf8))]
    }

    public init(item: NSSecureCoding?, typeIdentifier: String?) {
        super.init()
        guard let identifier = typeIdentifier else { return }
        let bytes: Data
        if let text = item as? NSString { bytes = Data((text as String).utf8) }
        else if let data = item as? NSData { bytes = data as Data }
        else if let url = item as? NSURL { bytes = Data((url as URL).absoluteString.utf8) }
        else { return }
        let mime = UTType(identifier)?.preferredMIMEType ?? identifier
        representations = [.init(identifier: identifier, format: mime, data: bytes)]
    }

    private func representation(for identifier: String) -> Representation? {
        representations.first { item in
            if item.identifier == identifier { return true }
            guard let offered = UTType(item.identifier), let requested = UTType(identifier) else { return false }
            return offered.conforms(to: requested)
        }
    }

    public func hasItemConformingToTypeIdentifier(_ typeIdentifier: String) -> Bool {
        representation(for: typeIdentifier) != nil
    }

    @discardableResult public func loadDataRepresentation(forTypeIdentifier typeIdentifier: String,
                                                          completionHandler: @escaping @Sendable (Data?, (any Error)?) -> Void) -> Progress {
        let result = representation(for: typeIdentifier)
        completionHandler(result?.data, result == nil ? CocoaError(.fileReadUnsupportedScheme) : nil)
        let progress = Progress(totalUnitCount: 1)
        progress.completedUnitCount = 1
        return progress
    }

    fileprivate static func read(_ mime: UnsafeMutableRawPointer, includingData: Bool) -> NSItemProvider {
        let provider = NSItemProvider()
        qs_mime_read(mime, includingData ? 1 : 0, Unmanaged.passUnretained(provider).toOpaque()) { raw, format, bytes, count in
            guard let raw, let format else { return }
            let provider = Unmanaged<NSItemProvider>.fromOpaque(raw).takeUnretainedValue()
            let formatName = String(cString: format)
            let type = UTType(mimeType: formatName)
            let data = bytes.map { Data(bytes: $0, count: count) } ?? Data()
            let identifier = type?.identifier ?? formatName
            provider.representations.append(.init(identifier: identifier, format: formatName, data: data))
        }
        return provider
    }
    fileprivate func write(to mime: UnsafeMutableRawPointer) -> Bool {
        for item in representations {
            item.data.withUnsafeBytes { bytes in
                qs_mime_write(mime, item.format, bytes.bindMemory(to: UInt8.self).baseAddress, bytes.count)
            }
        }
        return !representations.isEmpty
    }
}

struct TransferAction {
    var source: (() -> NSItemProvider)?
    var types: [String] = []
    var targeted: Binding<Bool>?
    var drop: (([NSItemProvider], CGPoint) -> Bool)?

    @MainActor func handle(_ phase: QSTransferPhase, mime: UnsafeMutableRawPointer?, point: CGPoint) -> Bool {
        switch phase {
        case QSWriteTransfer:
            guard let mime, let source else { return false }
            return source().write(to: mime)
        case QSTargetEnter, QSTargetLeave:
            targeted?.wrappedValue = phase == QSTargetEnter
            return true
        case QSValidateTransfer, QSPerformDrop:
            guard let mime, let drop else { return false }
            let provider = NSItemProvider.read(mime, includingData: phase == QSPerformDrop)
            guard types.contains(where: provider.hasItemConformingToTypeIdentifier) else { return false }
            return phase == QSValidateTransfer || drop([provider], point)
        default: return false
        }
    }
}

private nonisolated struct TransferView<Content: View>: Primitive {
    let content: Content
    let transfer: TransferAction
    @MainActor func elements(in context: Context) -> [Element] {
        let group = context.widget(QSGroup, transfer: transfer)
        let enabled = context.environment.isEnabled && context.environment.allowsHits
        qs_transfer_scope(group, enabled && transfer.source != nil ? 1 : 0, enabled && transfer.drop != nil ? 1 : 0)
        return context.children(of: content, inside: group)
    }
}

extension View {
    nonisolated public func onDrag(_ data: @escaping () -> NSItemProvider) -> some View {
        TransferView(content: self, transfer: TransferAction(source: data))
    }
    nonisolated public func onDrop(of supportedContentTypes: [UTType], isTargeted: Binding<Bool>?,
                                   perform action: @escaping ([NSItemProvider]) -> Bool) -> some View {
        onDrop(of: supportedContentTypes.map(\.identifier), isTargeted: isTargeted) { providers, _ in action(providers) }
    }
    nonisolated public func onDrop(of supportedContentTypes: [UTType], isTargeted: Binding<Bool>?,
                                   perform action: @escaping ([NSItemProvider], CGPoint) -> Bool) -> some View {
        onDrop(of: supportedContentTypes.map(\.identifier), isTargeted: isTargeted, perform: action)
    }
    nonisolated public func onDrop(of supportedTypes: [String], isTargeted: Binding<Bool>?,
                                   perform action: @escaping ([NSItemProvider]) -> Bool) -> some View {
        onDrop(of: supportedTypes, isTargeted: isTargeted) { providers, _ in action(providers) }
    }
    nonisolated public func onDrop(of supportedTypes: [String], isTargeted: Binding<Bool>?,
                                   perform action: @escaping ([NSItemProvider], CGPoint) -> Bool) -> some View {
        TransferView(content: self, transfer: TransferAction(types: supportedTypes, targeted: isTargeted, drop: action))
    }
}
