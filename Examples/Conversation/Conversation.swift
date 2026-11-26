import SwiftUI

private let ink = Color(red: 0.11, green: 0.14, blue: 0.20)
private let muted = Color(red: 0.32, green: 0.37, blue: 0.44)
private let paper = Color(red: 0.96, green: 0.97, blue: 0.98)
private let accent = Color(red: 0.16, green: 0.27, blue: 0.56)

private struct Message: Identifiable {
    let id = UUID()
    let author: String
    let text: String
    let outgoing: Bool
}
private struct Conversation: Identifiable {
    let id: String
    let initials: String
    let color: Color
    var messages: [Message]
}
private struct Inbox: View {
    @State private var selected = "Design group"
    @State private var draft = ""
    @State private var rooms = [
        Conversation(id: "Design group", initials: "DG", color: accent, messages: [
            Message(author: "Mira", text: "The first Linux window is up. Can you see the conversation?", outgoing: false),
            Message(author: "You", text: "Yes. The message bubbles and the composer are both here.", outgoing: true),
            Message(author: "Mira", text: "Great. Send a message when you’re ready.", outgoing: false)
        ]),
        Conversation(id: "Rowan", initials: "R", color: .teal, messages: [
            Message(author: "Rowan", text: "I’ll take a look this afternoon.", outgoing: false)
        ]),
        Conversation(id: "Notes to self", initials: "N", color: .purple, messages: [])
    ]
    private var index: Int { rooms.firstIndex { $0.id == selected }! }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Serein").font(.system(size: 30, weight: .bold))
                Text("Conversations").font(.headline).foregroundStyle(muted).padding(.top, 18)
                ForEach(rooms) { room in
                    Button {
                        selected = room.id
                        draft = ""
                    } label: {
                        HStack(spacing: 10) {
                            Avatar(initials: room.initials, color: room.color)
                            Text(room.id).font(.system(size: 15, weight: .semibold)).fixedSize()
                            Spacer(minLength: 0)
                        }
                        .padding(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 8).fill(room.id == selected ? accent.opacity(0.12) : Color.clear))
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
            }
            .padding(20)
            .frame(width: 236)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(paper)

            Divider()
            VStack(spacing: 0) {
                HStack(spacing: 12) {
                    Avatar(initials: rooms[index].initials, color: rooms[index].color)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(selected).font(.title2.bold())
                        Text("\(rooms[index].messages.count) messages").font(.footnote).foregroundStyle(muted)
                    }
                    Spacer()
                }
                .padding(20)
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        ForEach(rooms[index].messages) { message in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(message.author).font(.caption.bold()).foregroundStyle(muted)
                                Text(message.text)
                                    .font(.system(size: 16))
                                    .foregroundStyle(message.outgoing ? Color.white : ink)
                                    .padding(12)
                                    .background(RoundedRectangle(cornerRadius: 12).fill(message.outgoing ? accent : paper))
                            }
                            .frame(maxWidth: .infinity, alignment: message.outgoing ? .trailing : .leading)
                        }
                    }
                    .padding(20)
                }
                Divider()
                HStack(spacing: 10) {
                    TextField("Write a message", text: $draft)
                    Button("Send") {
                        rooms[index].messages.append(Message(author: "You", text: draft, outgoing: true))
                        draft = ""
                    }
                    .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .padding(16)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.white)
        }
        .foregroundStyle(ink)
    }
}
private struct Avatar: View {
    let initials: String, color: Color
    var body: some View {
        Text(initials).font(.system(size: 13, weight: .bold)).foregroundStyle(Color.white)
            .frame(width: 36, height: 36).background(Circle().fill(color))
    }
}

@main struct ConversationApp: App {
    var body: some Scene { WindowGroup("Serein • Conversations") { Inbox() }.defaultSize(width: 860, height: 520) }
}
