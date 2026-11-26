import SwiftUI

enum ContactScreen { case request, about, note, edit }

@MainActor @Observable final class ContactFlow {
    let start: ContactScreen
    var screen: ContactScreen
    var details = NicknameAndNote(note: "Weekend calls ☎️. Schedule: https://example.org/weekend")

    init(start: ContactScreen) {
        self.start = start
        screen = start
    }

    var contact: AboutContactModal.Contact {
        let participant = JoinRequestPreview.participant
        let nickname = [details.givenName, details.familyName].compactMap { $0 }.joined(separator: " ")
        var contact = AboutContactModal.Contact(id: participant.id, title: nickname.isEmpty ? participant.title : nickname)
        contact.titleNoNickname = participant.title
        contact.avatar = participant.avatar
        contact.color = participant.color
        contact.hasAvatar = participant.avatar != nil
        contact.about = "Usually around on weekends"
        contact.isInSystemContacts = true
        contact.systemGivenName = "Sam"
        contact.note = details.note
        return contact
    }
}

struct ContactFlowPreview: View {
    @State var model: ContactFlow
    @Environment(\.dismiss) private var dismiss

    private func closeAbout() {
        if model.start == .request { model.screen = .request } else { dismiss() }
    }

    private func closeNote() {
        if model.start == .note { dismiss() } else { model.screen = .about }
    }

    private var actions: AboutContactModal.Actions {
        var actions = AboutContactModal.Actions()
        actions.onClose = closeAbout
        actions.onOpenNotePreviewModal = { model.screen = .note }
        return actions
    }

    var body: some View {
        if model.screen == .request {
            JoinRequestPreview(title: model.contact.title, onAboutContact: { model.screen = .about })
        } else {
            AxoThemeOverride(theme: .forceDark) {
                AxoBaseDialog.Host {
                    switch model.screen {
                    case .about:
                        AboutContactModal(contact: model.contact, sharedGroupNames: ["Weekend plans", "Design review"],
                                          fromOrAddedByTrustedContact: true, actions: actions)
                    case .note:
                        NotePreviewModal(note: model.details.note ?? "", onClose: closeNote, onEdit: { model.screen = .edit })
                    case .edit:
                        EditNicknameAndNoteModal(avatar: .init(title: model.contact.title, color: model.contact.color, image: model.contact.avatar),
                                                 nicknameAndNote: model.details, onSave: { model.details = $0 },
                                                 onClose: {
                                                     if model.details.note != nil { model.screen = .note }
                                                     else if model.start == .note { dismiss() } else { model.screen = .about }
                                                 })
                    case .request: EmptyView()
                    }
                }.background(AxoColor.surfacePrimary)
            }
        }
    }
}
