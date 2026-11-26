import SwiftUI

struct JoinRequestPreview: View {
    var onApprove: () -> Void = {}
    var onDeny: () -> Void = {}
    var onAboutContact: () -> Void = {}
    var onClose: (() -> Void)?
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        AxoThemeOverride(theme: .forceDark) {
            AxoBaseDialog.Host {
                CallLinkPendingParticipantModal(conversation: Self.participant, isInSystemContacts: true,
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
