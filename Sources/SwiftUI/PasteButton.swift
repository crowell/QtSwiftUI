import QtBridge
import UniformTypeIdentifiers

public nonisolated struct PasteButton: View {
    private let types: [String]
    private let validatesPayload: Bool
    private let prepare: ([NSItemProvider]) -> (() -> Void)?

    public init(supportedContentTypes: [UTType], payloadAction: @escaping ([NSItemProvider]) -> Void) {
        self.init(supportedTypes: supportedContentTypes.map(\.identifier), payloadAction: payloadAction)
    }

    public init<Payload>(supportedContentTypes: [UTType], validator: @escaping ([NSItemProvider]) -> Payload?,
                         payloadAction: @escaping (Payload) -> Void) {
        self.init(supportedTypes: supportedContentTypes.map(\.identifier), validator: validator, payloadAction: payloadAction)
    }

    public init(supportedTypes: [String], payloadAction: @escaping ([NSItemProvider]) -> Void) {
        types = supportedTypes
        validatesPayload = false
        prepare = { items in { payloadAction(items) } }
    }

    public init<Payload>(supportedTypes: [String], validator: @escaping ([NSItemProvider]) -> Payload?,
                         payloadAction: @escaping (Payload) -> Void) {
        types = supportedTypes
        validatesPayload = true
        prepare = { items in validator(items).map { payload in { payloadAction(payload) } } }
    }

    public nonisolated var body: some View { PasteControl(configuration: self) }

    private nonisolated struct PasteControl: View {
        let configuration: PasteButton

        @MainActor func items(includingData: Bool) -> [NSItemProvider] {
            let clipboard = qs_clipboard_contents()
            for type in configuration.types {
                let items = NSItemProvider.clipboardItems(clipboard, matching: [type], includingData: includingData)
                if !items.isEmpty { return items }
            }
            return []
        }

        @MainActor var body: some View {
            let revision = qs_clipboard_revision()
            let offered = items(includingData: configuration.validatesPayload)
            let prepared = configuration.validatesPayload && !offered.isEmpty ? configuration.prepare(offered) : nil
            Button("Paste") {
                if let prepared, qs_clipboard_revision() == revision {
                    prepared()
                } else {
                    let current = items(includingData: true)
                    if !current.isEmpty { configuration.prepare(current)?() }
                }
            }.disabled(offered.isEmpty || (configuration.validatesPayload && prepared == nil))
        }
    }
}
