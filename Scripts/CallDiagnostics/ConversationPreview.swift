import SwiftUI

@MainActor @Observable final class ConversationPreviewModel {
    enum Panel { case messages, contact, media }
    var conversation: ConversationHeaderModel
    let timeline = TimelinePreviewModel()
    var searching = false
    var query = ""
    var panel = Panel.messages
    var tab = MediaGalleryTab.media
    var order = MediaSortOrder.date
    var onAudioCall: () -> Void = {}
    var onVideoCall: () -> Void = {}

    init() {
        var person = ConversationHeaderModel(id: "nyah", type: .direct, title: "Nyah Stroman")
        person.avatar = StickerSamples.fixtureImage("kitten-2-64-64.jpg")
        person.hasAvatar = person.avatar != nil
        person.isVerified = true
        conversation = person
    }

    func findMessage() {
        if !query.isEmpty, let i = timeline.rows.firstIndex(where: { $0.text.localizedCaseInsensitiveContains(query) }) {
            timeline.jump(to: i)
        }
    }

    var contact: AboutContactModal.Contact {
        var person = AboutContactModal.Contact(id: conversation.id, title: conversation.title)
        person.avatar = conversation.avatar
        person.hasAvatar = conversation.hasAvatar
        return person
    }

    var contactActions: AboutContactModal.Actions {
        var actions = AboutContactModal.Actions()
        actions.onClose = { self.panel = .messages }
        return actions
    }

    var actions: ConversationHeaderActions {
        var actions = ConversationHeaderActions()
        actions.onSearchInConversation = { self.searching.toggle() }
        actions.onViewConversationDetails = { self.panel = .contact }
        actions.onOutgoingAudioCall = onAudioCall
        actions.onOutgoingVideoCall = onVideoCall
        actions.onViewAllMedia = { self.panel = .media }
        actions.onMuteExpirationChange = { self.conversation.isMuted = $0 != nil }
        actions.onDisappearingMessagesChange = { self.conversation.expireTimer = $0 }
        actions.onPin = { self.conversation.isPinned = true }
        actions.onUnpin = { self.conversation.isPinned = false }
        actions.onMarkUnread = { self.conversation.markedUnread = true }
        return actions
    }
}

struct ConversationPreview: View {
    @State var model = ConversationPreviewModel()

    var body: some View {
        @Bindable var model = model
        switch model.panel {
        case .messages:
            VStack(spacing: 0) {
                ConversationHeader(conversation: model.conversation, outgoingCallButtonStyle: .both, actions: model.actions)
                if model.searching {
                    SearchInput(value: $model.query, placeholder: "Search in conversation", focusesOnAppear: true,
                                onClear: { model.query = ""; model.searching = false }, onEnter: model.findMessage)
                }
                TimelinePreview(model: model.timeline)
            }
            .background(AxoColor.surfacePrimary)
            .axoLayerHost()
        case .contact:
            AxoBaseDialog.Host { AboutContactModal(contact: model.contact, actions: model.contactActions) }
                .background(AxoColor.surfacePrimary)
        case .media:
            GalleryPanel(tab: $model.tab, order: $model.order, onBack: { model.panel = .messages },
                         attachments: GalleryMediaSample.attachments)
        }
    }
}
