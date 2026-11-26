import SwiftUI

struct JoinRequestPreview: View {
    var title: String?
    var onApprove: () -> Void = {}
    var onDeny: () -> Void = {}
    var onAboutContact: () -> Void = {}
    var onClose: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    private var conversation: CallingConversation {
        var participant = Self.participant
        if let title { participant.title = title }
        return participant
    }
    var body: some View {
        AxoThemeOverride(theme: .forceDark) {
            AxoBaseDialog.Host {
                CallLinkPendingParticipantModal(conversation: conversation, isInSystemContacts: true,
                    sharedGroupNames: ["Weekend plans", "Design review"], approveUser: onApprove, denyUser: onDeny,
                    onClose: onClose ?? { dismiss() }, toggleAboutContactModal: onAboutContact)
            }.background(AxoColor.surfacePrimary)
        }
    }
    static var participant: CallingConversation {
        CallingConversation(id: "sample-guest", title: "Sam Rivera", color: "A170",
                            avatar: GalleryMediaSample.attachments.compactMap(\.image).first)
    }
}
