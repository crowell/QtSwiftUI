import SwiftUI

@MainActor @Observable final class CallsPreviewModel {
    let history: CallHistoryModel
    let contacts: [CallsNewCallConversation]
    let created = CallLinkModel(link: nil)
    let details: CallLinkModel
    var width: CGFloat = 320
    var newCallQuery = ""
    var readIDs: Set<String> = []
    var outgoing: String?

    init(history: CallHistoryModel = CallHistoryModel()) {
        self.history = history
        let conversations = history.history.map(\.conversation).filter { $0.conversationType != .callLink }
        var ids = Set<String>()
        contacts = conversations.filter { ids.insert($0.id).inserted }.map {
            CallsNewCallConversation(conversation: $0, isGroup: $0.conversationType == .group)
        }
        var link = CallLinkModel.admin
        link.name = "Weekend plans"
        details = CallLinkModel(link: link)
    }
    var unread: Int {
        history.history.filter { $0.wasMissed && $0.group.children.contains { !readIDs.contains($0.callId) } }.count
    }
    var matches: [CallsNewCallConversation] {
        let term = newCallQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        return contacts.filter { term.isEmpty || $0.conversation.title.localizedCaseInsensitiveContains(term) }
            .sorted { $0.conversation.title.localizedCaseInsensitiveCompare($1.conversation.title) == .orderedAscending }
    }
    func clearHistory() {
        history.history.removeAll()
        readIDs.removeAll()
        for link in [details, created] {
            link.link = nil
            link.dialog = nil
        }
    }
    func outgoingCall(to id: String, video: Bool) {
        guard let conversation = contacts.first(where: { $0.id == id }) else { return }
        outgoing = "\(video ? "Video" : "Audio") call to \(conversation.conversation.title)"
    }
}

struct CallsTabPreview: View {
    @State var model = CallsPreviewModel()
    var collapsed = false
    var toggleRail: (Bool) -> Void = { _ in }
    @Environment(\.i18n) private var i18n

    private var actions: CallsTabActions {
        var actions = CallsTabActions()
        actions.savePreferredLeftPaneWidth = { model.width = $0 }
        actions.onToggleNavTabsCollapse = toggleRail
        actions.onClearCallHistory = model.clearHistory
        actions.onMarkCallHistoryRead = { _, callID in model.readIDs.insert(callID) }
        actions.onCreateCallLink = {
            var link = CallLinkModel.admin
            link.name = ""
            model.created.link = link
            model.created.dialog = .manage
        }
        actions.onCall = { item in
            if item.group.type == .adhoc { model.outgoing = "Join \(item.conversation.title)" }
            else { model.outgoingCall(to: item.peerId, video: item.group.type != .audio) }
        }
        actions.onOutgoingAudioCallInConversation = { model.outgoingCall(to: $0, video: false) }
        actions.onOutgoingVideoCallInConversation = { model.outgoingCall(to: $0, video: true) }
        return actions
    }

    var body: some View {
        @Bindable var history = model.history
        @Bindable var calls = model
        CallsTab(preferredLeftPaneWidth: model.width, navTabsCollapsed: collapsed, hasPendingUpdate: true,
                 hasAnyAdminCallLinks: model.details.link != nil || model.created.link != nil, hasActiveCall: false, callsListItems: history.results,
                 historyQuery: $history.query, missedOnly: $history.missedOnly, newCallConversations: model.matches,
                 newCallQuery: $calls.newCallQuery, actions: actions) { _, group, close in
            CallLinkPreview(model: model.details, group: group)
                .onChange(of: model.details.link == nil) { _, removed in if removed { close() } }
        } renderConversationDetails: { id, group in
            if let contact = model.contacts.first(where: { $0.id == id })?.conversation {
                VStack(spacing: 12) {
                    contact.avatarView(size: 80, i18n: i18n)
                    CSSText(contact.title, type: .titleLarge, alignment: .center)
                    if let group, history.history.contains(where: { $0.group == group }) {
                        CallHistoryGroupPanelSection(callHistoryGroup: group)
                    }
                }.padding(.horizontal, 20)
            }
        }
        .background(AxoColor.surfacePrimary)
        .overlay { CallLinkPreview(model: model.created).linkDialog }
        .overlay {
            if let outgoing = model.outgoing {
                AxoBaseDialog.Host {
                    AxoConfirmDialog.Root(title: outgoing, description: "Local call preview") {
                        AxoConfirmDialog.Ok(i18n("icu:ok")) { model.outgoing = nil }
                    }
                }
            }
        }
        .axoLayerHost()
        .environment(\.conversationListNow, CallHistoryModel.now)
        .environment(\.timeZone, .gmt)
    }
}
