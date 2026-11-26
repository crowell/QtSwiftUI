import SwiftUI

@MainActor @Observable final class TimelinePreviewModel {
    struct Entry: Identifiable {
        let id: String
        let text: String
        let direction: MessageDirection
        let timestamp: Date
    }

    static let now = Date(timeIntervalSince1970: 1_793_793_600)
    let rows: [Entry]
    let firstUnread = 8
    var nearBottom: Bool?
    var newestRead: String?
    var targetIndex: Int?
    var jumpCount = 0

    init() {
        let messages: [(MessageDirection, String)] = [
            (.incoming, "Are we still on for the ferry?"),
            (.outgoing, "Yes! I have the tickets."),
            (.incoming, "Which pier are we leaving from?"),
            (.outgoing, "Pier 52, on the waterfront."),
            (.incoming, "I’ll meet you at the entrance."),
            (.outgoing, "Sounds good. I’m on my way."),
            (.incoming, "Do we have time to grab coffee?"),
            (.outgoing, "There’s a café next to the terminal."),
            (.incoming, "I’m here. What would you like?"),
            (.outgoing, "A cappuccino, please."),
            (.incoming, "Got it. See you in a minute!")
        ]
        rows = messages.enumerated().map { i, message in
            Entry(id: "ferry-\(i)", text: message.1, direction: message.0,
                  timestamp: Self.now.addingTimeInterval(Double(i - messages.count) * 60))
        }
    }

    func jump(to index: Int) {
        targetIndex = index
        jumpCount += 1
    }
}

struct TimelinePreview: View {
    @State var model = TimelinePreviewModel()

    var body: some View {
        Timeline(id: "ferry", items: model.rows.map(\.id), haveNewest: true, haveOldest: true,
                 oldestUnseenIndex: model.firstUnread, totalUnseen: model.rows.count - model.firstUnread,
                 unreadCount: model.rows.count - model.firstUnread, unreadMentionsCount: 1,
                 isNearBottom: model.nearBottom, scrollToIndex: model.targetIndex, scrollToIndexCounter: model.jumpCount,
                 getTimestampForMessage: { id in model.rows.first { $0.id == id }?.timestamp }) { props in
            let row = model.rows[props.index]
            SampleMessage(bubbleColor: .preset("ultramarine"), direction: row.direction, text: row.text,
                          timestamp: row.timestamp, status: .read)
        } renderHeroRow: {
            TimelineDateHeader(timestamp: TimelinePreviewModel.now)
        } renderTypingBubble: {
            EmptyView()
        } setIsNearBottom: { _, near in model.nearBottom = near }
          scrollToOldestUnreadMention: { _ in model.jump(to: model.firstUnread) }
          markMessageRead: { model.newestRead = $0 }
        .background(AxoColor.surfacePrimary)
        .environment(\.conversationListNow, TimelinePreviewModel.now)
        .environment(\.timeZone, TimeZone(identifier: "America/Los_Angeles")!)
    }
}
