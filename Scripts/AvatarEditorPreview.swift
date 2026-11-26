import SwiftUI
import SignalI18n

struct AvatarEditorPreview: View {
    @Environment(\.i18n) var i18n
    @Environment(\.dismiss) var dismiss
    var body: some View {
        AxoBaseDialog.Host {
            AxoDialog.Content(size: .md) {
                AxoDialog.Header { AxoDialog.Title(i18n("icu:LeftPaneSetGroupMetadataHelper__avatar-modal-title")) }
                AvatarEditor(avatarColor: AxoTokens.Avatar.allColorNames[0], conversationTitle: "Ferry crew",
                             isGroup: true, isInsideDialog: true, userAvatarData: AvatarEditor.defaultAvatars(isGroup: true),
                             callbacks: {
                                 var actions = AvatarEditor.Callbacks()
                                 actions.onCancel = { dismiss() }
                                 actions.onSave = { _ in dismiss() }
                                 actions.onPhotoPicked = { url in print("Photo selected: \(url.absoluteString)") }
                                 return actions
                             }())
            }
        }
        .background(AxoColor.surfaceSecondary)
    }
}
