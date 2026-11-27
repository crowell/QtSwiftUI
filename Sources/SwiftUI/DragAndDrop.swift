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
    private var fileLinks: Representation?
    public var registeredTypeIdentifiers: [String] {
        let types = representations.map(\.identifier)
        return fileLinks == nil || types.contains(UTType.fileURL.identifier) ? types : types + [UTType.fileURL.identifier]
    }

    public override init() { super.init() }
    public init(object: NSString) {
        super.init()
        representations = [.init(identifier: UTType.utf8PlainText.identifier, format: "text/plain", data: Data((object as String).utf8))]
    }

    public init(object: NSURL) {
        super.init()
        let url = object as URL
        let types: [UTType] = url.isFileURL ? [.fileURL, .url] : [.url]
        representations = types.map { Representation(identifier: $0.identifier, format: "text/uri-list", data: Data(url.absoluteString.utf8)) }
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

    fileprivate func representation(for identifier: String) -> Representation? {
        if identifier == UTType.fileURL.identifier, let fileLinks { return fileLinks }
        return representations.first { item in
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
            if type == .url, let list = String(data: data, encoding: .utf8) {
                let files = list.split(whereSeparator: \.isNewline).filter { line in
                    !line.hasPrefix("#") && URL(string: String(line))?.isFileURL == true
                }
                if !files.isEmpty {
                    let contents = files.joined(separator: "\r\n") + "\r\n"
                    provider.fileLinks = .init(identifier: UTType.fileURL.identifier, format: formatName, data: Data(contents.utf8))
                }
            }
        }
        return provider
    }
    fileprivate static func dropItems(_ mime: UnsafeMutableRawPointer, includingData: Bool) -> [NSItemProvider] {
        let item = read(mime, includingData: includingData)
        if let urls = item.representation(for: UTType.url.identifier),
           let list = String(data: urls.data, encoding: .utf8) {
            let entries = list.split(whereSeparator: \.isNewline).compactMap { line -> URL? in
                guard !line.hasPrefix("#"), let url = URL(string: String(line)), url.scheme != nil else { return nil }
                return url
            }
            if !entries.isEmpty {
                let providers = entries.map { NSItemProvider(object: $0 as NSURL) }
                // Other MIME formats describe the offer as a whole. Retain them once.
                providers[0].representations += item.representations.filter { $0.format != urls.format }
                return providers
            }
        }
        return [item]
    }

    func transferData(for types: [UTType]) -> [(Data, UTType)] {
        for type in types {
            guard let match = representation(for: type.identifier) else { continue }
            if type.conforms(to: .url), let list = String(data: match.data, encoding: .utf8) {
                return list.split(whereSeparator: \.isNewline).compactMap { entry in
                    guard !entry.hasPrefix("#"), let url = URL(string: String(entry)), url.scheme != nil else { return nil }
                    return (Data(url.absoluteString.utf8), type)
                }
            }
            return [(match.data, type)]
        }
        return []
    }

    static func clipboardItems(_ mime: UnsafeMutableRawPointer?, matching types: [String], includingData: Bool) -> [NSItemProvider] {
        (0..<qs_clipboard_item_count(mime)).compactMap { index in
            guard let item = qs_clipboard_item(mime, index) else { return nil }
            let offered = read(item, includingData: false)
            guard types.contains(where: offered.hasItemConformingToTypeIdentifier) else { return nil }
            return includingData ? read(item, includingData: true) : offered
        }
    }

    fileprivate func write(to mime: UnsafeMutableRawPointer) -> Bool {
        for item in representations {
            var wireData = item.data
            if item.format == "text/uri-list", !wireData.isEmpty, wireData.last != 10 { wireData.append(contentsOf: [13, 10]) }
            wireData.withUnsafeBytes { bytes in
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
    var delegate: (any DropDelegate)?
    var clipboardCommand: QSTransferPhase?
    var copyItems: (() -> [NSItemProvider])?
    var pasteItems: (([NSItemProvider]) -> Bool)?

    @MainActor func response(_ phase: QSTransferPhase, mime: UnsafeMutableRawPointer?, point: CGPoint) -> Int32 {
        guard let delegate else {
            if phase == QSUpdateTransfer || phase == QSUpdateExternalTransfer { return Int32(QSDropUnchanged.rawValue) }
            return handle(phase, mime: mime, point: point) ? 1 : 0
        }
        guard phase != QSTargetFinish, let mime else { return 0 }
        let providers = NSItemProvider.dropItems(mime, includingData: phase == QSPerformDrop)
        let payload = phase == QSPerformDrop ? DropInfo.Payload() : nil
        payload?.items = providers
        defer { payload?.items.removeAll() }
        let info = DropInfo(position: point, offered: providers, payload: payload)
        switch phase {
        case QSValidateTransfer: return info.hasItemsConforming(to: types) && delegate.validateDrop(info: info) ? 1 : 0
        case QSTargetEnter: delegate.dropEntered(info: info)
        case QSTargetLeave: delegate.dropExited(info: info)
        case QSPerformDrop: return delegate.performDrop(info: info) ? 1 : 0
        case QSUpdateTransfer, QSUpdateExternalTransfer:
            // The desktop hosting view proposes copy when an update returns nil.
            guard let proposal = delegate.dropUpdated(info: info) else { return Int32(QSDropCopy.rawValue) }
            let operation = phase == QSUpdateExternalTransfer ? proposal.operationOutsideApplication ?? proposal.operation : proposal.operation
            return Int32(operation.nativeProposal.rawValue)
        default: break
        }
        return 0
    }

    @MainActor private func handle(_ phase: QSTransferPhase, mime: UnsafeMutableRawPointer?, point: CGPoint) -> Bool {
        switch phase {
        case QSCopyItems, QSCutItems:
            guard let mime, let copyItems, clipboardCommand == phase else { return false }
            for item in copyItems() where !item.registeredTypeIdentifiers.isEmpty {
                if let destination = qs_clipboard_add_item(mime) { _ = item.write(to: destination) }
            }
            return true
        case QSPasteItems:
            guard let mime, let pasteItems else { return false }
            let providers = NSItemProvider.clipboardItems(mime, matching: types, includingData: true)
            return !providers.isEmpty && pasteItems(providers)
        case QSWriteTransfer:
            guard let mime, let source else { return false }
            return source().write(to: mime)
        case QSTargetEnter, QSTargetLeave, QSTargetFinish:
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

private nonisolated struct PasteDestination<Content: View, T: Transferable>: View {
    let content: Content
    let paste: TypedPaste<T>

    @MainActor var body: some View {
        content.onPasteCommand(of: T.importedContentTypes()) { items in paste.deliver(items) }
    }
}

nonisolated struct TransferView<Content: View>: Primitive {
    let content: Content
    let transfer: TransferAction
    @MainActor func elements(in context: Context) -> [Element] {
        let group = context.widget(QSGroup, transfer: transfer)
        let enabled = context.environment.isEnabled && context.environment.allowsHits
        qs_clipboard_scope(group, enabled ? transfer.clipboardCommand.map { Int32($0.rawValue) } ?? -1 : -1)
        qs_transfer_scope(group, enabled && transfer.source != nil ? 1 : 0, enabled && (transfer.drop != nil || transfer.delegate != nil) ? 1 : 0)
        return context.children(of: content, inside: group)
    }
}

extension View {
    nonisolated public func onCopyCommand(perform payloadAction: (() -> [NSItemProvider])?) -> some View {
        TransferView(content: self, transfer: TransferAction(clipboardCommand: payloadAction == nil ? nil : QSCopyItems, copyItems: payloadAction))
    }
    nonisolated public func onCutCommand(perform payloadAction: (() -> [NSItemProvider])?) -> some View {
        TransferView(content: self, transfer: TransferAction(clipboardCommand: payloadAction == nil ? nil : QSCutItems, copyItems: payloadAction))
    }
    nonisolated public func onPasteCommand(of supportedContentTypes: [UTType], perform payloadAction: @escaping ([NSItemProvider]) -> Void) -> some View {
        onPasteCommand(of: supportedContentTypes.map(\.identifier), perform: payloadAction)
    }
    nonisolated public func onPasteCommand<Payload>(of supportedContentTypes: [UTType], validator: @escaping ([NSItemProvider]) -> Payload?,
                                                    perform payloadAction: @escaping (Payload) -> Void) -> some View {
        onPasteCommand(of: supportedContentTypes.map(\.identifier), validator: validator, perform: payloadAction)
    }
    nonisolated public func onPasteCommand(of supportedTypes: [String], perform payloadAction: @escaping ([NSItemProvider]) -> Void) -> some View {
        onPasteCommand(of: supportedTypes, validator: { $0 }, perform: payloadAction)
    }
    nonisolated public func onPasteCommand<Payload>(of supportedTypes: [String], validator: @escaping ([NSItemProvider]) -> Payload?,
                                                    perform payloadAction: @escaping (Payload) -> Void) -> some View {
        TransferView(content: self, transfer: TransferAction(types: supportedTypes, clipboardCommand: QSPasteItems, pasteItems: { items in
            guard let payload = validator(items) else { return false }
            payloadAction(payload)
            return true
        }))
    }
    nonisolated public func pasteDestination<T>(for payloadType: T.Type = T.self, action: @escaping ([T]) -> Void,
                                                validator: @escaping ([T]) -> [T] = { $0 }) -> some View where T: Transferable {
        let paste = TypedPaste<T> { items in
            let accepted = validator(items)
            if !accepted.isEmpty { action(accepted) }
        }
        return PasteDestination(content: self, paste: paste)
    }

    nonisolated public func dropDestination(for payloadType: URL.Type = URL.self,
                                             action: @escaping ([URL], CGPoint) -> Bool,
                                             isTargeted: @escaping (Bool) -> Void = { _ in }) -> some View {
        let target = Binding(get: { false }, set: { isTargeted($0) })
        return onDrop(of: [UTType.url], isTargeted: target) { providers, location in
            let urls = providers.flatMap { provider -> [URL] in
                guard let data = provider.representation(for: UTType.url.identifier)?.data,
                      let list = String(data: data, encoding: .utf8) else { return [] }
                return list.split(whereSeparator: \.isNewline).compactMap { entry in
                    guard !entry.hasPrefix("#"), let url = URL(string: String(entry)), url.scheme != nil else { return nil }
                    return url
                }
            }
            return !urls.isEmpty && action(urls, location)
        }
    }
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
