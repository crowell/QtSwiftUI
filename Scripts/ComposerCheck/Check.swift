import SwiftUI
import Foundation

@main struct ComposerCheck: App {
    @State private var text = ""
    @State private var submitCount = 0
    private let controller = ComposerController()
    static let draft = "Hi \u{FFFC}, the ferry leaves at 10:30.\nMeet at Pier 4?"
    static let mention = BodyRange(start: 3, length: 1, kind: .mention(aci: "member-1", conversationID: "member-1", replacementText: "Alice"))
    static let bold = BodyRange(start: 26, length: 5, kind: .formatting(.bold))

    init() {
        let document = LinuxComposerDocument(), model = ComposerController()
        model.textView = document
        model.load(body: Self.draft, ranges: [Self.mention, Self.bold])
        precondition(model.outgoing().body == Self.draft && model.outgoing().ranges == [Self.mention, Self.bold])
        let pill = document.text.range(of: "@Alice")!
        document.selection = .init(range: pill)
        model.toggle(.italic)
        precondition(model.outgoing().ranges.contains(BodyRange(start: 3, length: 1, kind: .formatting(.italic))))
        var edited = document.text
        edited.characters.remove(at: edited.index(beforeCharacter: pill.upperBound))
        document.receive(edited)
        precondition(document.string.hasPrefix("Hi , the ferry") && model.mentionSpans().isEmpty)
        controller.load(body: Self.draft, ranges: [Self.mention, Self.bold])
    }

    var body: some Scene {
        WindowGroup("Serein • Message composer") {
            CompositionInput(text: $text, showViewOnceButton: true, onSubmit: {
                let outgoing = controller.outgoing()
                if ProcessInfo.processInfo.environment["SEREIN_COMPOSER_VERIFY"] == "1" {
                    submitCount += 1
                    if submitCount == 1 {
                        precondition(outgoing.body == Self.draft + " Yes")
                        precondition(outgoing.ranges == [Self.mention, Self.bold])
                    } else {
                        precondition(outgoing.body == Self.draft.replacingOccurrences(of: "\u{FFFC}", with: "") + " Yes")
                        precondition(outgoing.ranges == [BodyRange(start: 25, length: 5, kind: .formatting(.bold))])
                    }
                    print("Verified composer submission", submitCount)
                }
            })
            .environment(\.composerController, controller)
            .padding(16)
        }.defaultSize(width: 480, height: 110)
    }
}
