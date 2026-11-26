import SwiftUI

@MainActor @Observable final class CallHistoryModel {
    static let now = Date(timeIntervalSince1970: 1_793_793_600)
    var query = ""
    var missedOnly = false
    var selected: CallsTabSelectedView?
    var onCall: (CallsListItem) -> Void = { _ in }
    var onCreateLink: () -> Void = {}
    var pending = false
    var creatingLink = false
    var history: [CallsListItem] = {
        let records: [(String, CallType, CallDirection, CallStatus, String)] = [
            ("Alice", .audio, .incoming, .missed, "A130"),
            ("Design review", .group, .outgoing, .joined, "A190"),
            ("Sam Rivera", .video, .incoming, .accepted, "A170"),
            ("Weekend plans", .adhoc, .outgoing, .genericAdhocCall, "A200"),
            ("Mina Park", .audio, .incoming, .declined, "A140"),
            ("Alex Chen", .video, .incoming, .missed, "A150"),
            ("Jordan Lee", .audio, .outgoing, .accepted, "A180"),
            ("Book club", .group, .outgoing, .joined, "A110")
        ]
        return records.enumerated().map { index, record in
            let (title, type, direction, status, color) = record
            let id = "sample-\(index)"
            let date = now.addingTimeInterval(-Double(5 + index * 37) * 60)
            let group = CallHistoryGroup(type: type, direction: direction, status: status, timestamp: date,
                                         children: [.init(callId: id, timestamp: date)])
            return CallsListItem(id: id, peerId: id, group: group,
                conversation: CallingConversation(id: id, title: title, color: color,
                    conversationType: type == .group ? .group : type == .adhoc ? .callLink : .direct),
                isMutedForCalls: index == 2, isAnybodyInCall: index == 1)
        }
    }()

    var results: [CallsListItem]? {
        guard !pending else { return nil }
        let filter = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return history.filter { (!missedOnly || $0.wasMissed) && (filter.isEmpty || $0.conversation.title.localizedCaseInsensitiveContains(filter)) }
    }
}

struct CallHistoryPreview: View {
    @State var model = CallHistoryModel()
    var body: some View {
        @Bindable var model = model
        CallsList(items: model.results, query: $model.query, missedOnly: $model.missedOnly, hasActiveCall: false,
                  isCreatingCallLink: model.creatingLink, selected: model.selected?.callHistoryGroup,
                  onCreateCallLink: model.onCreateLink, onSelect: { model.selected = $0 }, onCall: model.onCall)
            .environment(\.searchInputMarginReset, true)
            .environment(\.conversationListNow, CallHistoryModel.now)
            .environment(\.timeZone, TimeZone(secondsFromGMT: 0)!)
            .background(AxoColor.surfacePrimary)
    }
}
