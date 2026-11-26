import SwiftUI
#if os(Linux)
import QtBridge
#else
import AppKit
#endif

@MainActor @Observable final class CallLinkModel {
    enum Dialog { case manage, rename }
    var link: CallLinkInfo?
    var dialog: Dialog?
    var returnToManager = false
    var activeOnServer = false
    var onCopy: (String) -> Void = { url in
        #if os(Linux)
        qs_clipboard_text(url)
        #else
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(url, forType: .string)
        #endif
    }
    var onShare: () -> Void = {}
    var onJoin: () -> Void = {}

    init(link: CallLinkInfo? = CallLinkModel.admin) { self.link = link }

    func rename() {
        returnToManager = dialog == .manage
        dialog = .rename
    }
    func closeName() {
        dialog = returnToManager ? .manage : nil
        returnToManager = false
    }
}

struct CallLinkPreview: View {
    @State var model = CallLinkModel()
    var group = CallLinkModel.history
    var body: some View {
        CallLinkDetails(callLink: model.link, callHistoryGroup: group, isCallActiveOnServer: model.activeOnServer,
            onDeleteCallLink: { model.link = nil }, onOpenCallLinkAddNameModal: model.rename,
            onStartCallLinkLobby: model.onJoin, onShareCallLinkViaSignal: model.onShare,
            onCopyCallLink: model.onCopy, onUpdateCallLinkRestrictions: { model.link?.requiresAdminApproval = $0 })
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(AxoColor.surfacePrimary)
            .overlay { linkDialog }
            .environment(\.conversationListNow, CallLinkModel.now)
            .environment(\.timeZone, .gmt)
    }

    @ViewBuilder var linkDialog: some View {
        if let link = model.link, let dialog = model.dialog {
            AxoBaseDialog.Host {
                switch dialog {
                case .manage:
                    CallLinkEditModal(callLink: link, hasActiveCall: model.activeOnServer, onClose: { model.dialog = nil },
                        onCopyCallLink: { model.onCopy(link.webURL) }, onOpenCallLinkAddNameModal: model.rename,
                        onUpdateCallLinkRestrictions: { model.link?.requiresAdminApproval = $0 },
                        onShareCallLinkViaSignal: model.onShare, onStartCallLinkLobby: model.onJoin)
                case .rename:
                    CallLinkAddNameModal(callLink: link, onClose: model.closeName, onUpdateCallLinkName: { model.link?.name = $0 })
                }
            }
        }
    }
}

struct CallHistoryBrowserPreview: View {
    @State var history = CallHistoryModel()
    @State var details: CallLinkModel = {
        var sample = CallLinkModel.admin
        sample.name = "Weekend plans"
        return CallLinkModel(link: sample)
    }()
    @State var created = CallLinkModel()

    var body: some View {
        Group {
            if case .callLink(_, let group) = history.selected {
                ConversationPanel(onBack: { history.selected = nil }, header: { Color.clear }) {
                    ScrollView { CallLinkPreview(model: details, group: group) }
                }
            } else {
                CallHistoryPreview(model: history)
                    .overlay { CallLinkPreview(model: created).linkDialog }
                    .onAppear {
                        history.onCreateLink = {
                            var link = CallLinkModel.admin
                            link.name = ""
                            created.link = link
                            created.dialog = .manage
                        }
                    }
            }
        }
    }
}

struct NicknamePreview: View {
    @Environment(\.dismiss) var dismiss
    @State var contact = NicknameAndNote(givenName: "Sam", note: "Prefers video calls.")
    let avatar = ConversationAvatarData(title: "Sam Rivera", color: "A170")

    var body: some View {
        AxoBaseDialog.Host {
            EditNicknameAndNoteModal(avatar: avatar, nicknameAndNote: contact, onSave: { contact = $0 }, onClose: { dismiss() })
        }.background(AxoColor.surfacePrimary)
    }
}
