import SwiftUI

struct ChatColorPickerPreview: View {
    private struct Editor {
        var initial: CustomChatColor?
        var duplicate = false
    }
    @State private var colors = Self.customColors
    @State private var preset: String?
    @State private var customID: Int? = 3
    @State private var editor: Editor?

    private func select(preset: String? = nil, custom: Int? = nil) {
        self.preset = preset
        customID = custom
    }

    private func save(_ color: BubbleColor, replacing id: Int? = nil) {
        if let id, let index = colors.firstIndex(where: { $0.id == id }) {
            colors[index].color = color
            select(custom: id)
        } else {
            let next = (colors.map(\.id).max() ?? 0) + 1
            colors.append(CustomChatColor(id: next, color: color))
            select(custom: next)
        }
    }

    @ViewBuilder private var dialog: some View {
        if let editor {
            let data = editor.initial?.color.data
            let gradient = data?.gradient.map { (start: $0.start.rgb24, end: $0.end.rgb24, angle: Int((270 - $0.deg).rounded()) % 360) }
            AxoBaseDialog.Host {
                CustomColorEditorDialog(initialSolid: data?.solid?.rgb24, initialGradient: gradient,
                                        onClose: { self.editor = nil }, onSave: { save($0, replacing: editor.duplicate ? nil : editor.initial?.id) })
            }
        }
    }

    var body: some View {
        ScrollView {
            ChatColorPicker(conversationId: "preview", customChatColors: colors, selectedPreset: preset,
                selectedCustomColorId: customID, onSelectPreset: { select(preset: $0) },
                onSelectCustomColor: { select(custom: $0) }, onAddCustomColor: { editor = Editor() },
                onEditCustomColor: { editor = Editor(initial: $0) }, onDuplicateCustomColor: { editor = Editor(initial: $0, duplicate: true) },
                onRemoveCustomColor: { item in
                    colors.removeAll { $0.id == item.id }
                    if customID == item.id { select() }
                }, onResetChatColor: { select() }, onResetAll: { select() })
        }
        .background(AxoColor.surfacePrimary)
        .axoViewport()
        .axoLayerHost()
        .overlay { dialog }
        .environment(\.conversationListNow, Date(timeIntervalSince1970: 1_793_793_600))
        .environment(\.timeZone, TimeZone(secondsFromGMT: 0)!)
    }
}

private extension RGBA {
    var rgb24: UInt32 {
        func byte(_ component: Double) -> UInt32 { UInt32((min(1, max(0, component)) * 255).rounded()) }
        return byte(r) << 16 | byte(g) << 8 | byte(b)
    }
}
