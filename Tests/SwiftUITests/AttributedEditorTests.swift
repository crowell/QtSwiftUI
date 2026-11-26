import QtBridge
import XCTest
@testable import SwiftUI

private enum MentionAttribute: AttributedStringKey {
    typealias Value = String
    static let name = "Test.Mention"
}

final class AttributedEditorTests: XCTestCase {
    @MainActor func testTypingSelectionAndUndoPreserveCustomAttributes() async {
        var mention = AttributedString("@Alice")
        mention[MentionAttribute.self] = "member-1"
        mention.backgroundColor = .yellow
        var text = AttributedString("Hi ") + mention + AttributedString("!")
        var selection = AttributedTextSelection()
        let host = Host(title: "Rich composer") { context in
            TextEditor(text: Binding(get: { text }, set: { text = $0 }),
                       selection: Binding(get: { selection }, set: { selection = $0 })).resolve(context)
        }
        defer { host.close() }
        host.open(width: 300, height: 95)
        qs_flush()
        _ = qs_click_point(host.window, 12, 10)
        let pill = text.range(of: "@Alice")!
        selection = .init(range: pill)
        host.update()
        qs_flush()
        _ = qs_send_key_sequence(host.window, "Backspace")
        XCTAssertEqual(String(text.characters), "Hi !")
        _ = qs_send_key_sequence(host.window, "Ctrl+Z")
        XCTAssertEqual(String(text.characters), "Hi @Alice!")
        guard let restored = text.range(of: "@Alice") else { return }
        XCTAssertEqual(text[restored][MentionAttribute.self], "member-1")
        XCTAssertEqual(text[restored].backgroundColor, .yellow)
        var typing = AttributeContainer()
        typing.foregroundColor = .red
        selection = .init(insertionPoint: text.endIndex, typingAttributes: typing)
        host.update()
        qs_flush()
        let input = " 🎉"
        XCTAssertEqual(input.withCString { qs_commit_text(host.window, $0, input.utf8.count) }, 1)
        XCTAssertEqual(String(text.characters), "Hi @Alice! 🎉")
        XCTAssertEqual(text.runs[text.index(beforeCharacter: text.endIndex)].foregroundColor, .red)
        XCTAssertEqual(selection.indices(in: text), .insertionPoint(text.endIndex))
    }

    @MainActor func testBindingCanExpandADeletionAndRepositionTheCaret() async {
        var text: AttributedString = "Hi @Alice!"
        var selection = AttributedTextSelection()
        let host = Host(title: "Atomic edit") { context in
            TextEditor(text: Binding(get: { text }, set: { incoming in
                if String(incoming.characters) == "Hi @Alic!" {
                    text = "Hi !"
                    selection = .init(insertionPoint: text.index(text.startIndex, offsetByCharacters: 3))
                } else {
                    text = incoming
                }
            }), selection: Binding(get: { selection }, set: { selection = $0 })).resolve(context)
        }
        defer { host.close() }
        host.open(width: 280, height: 85)
        _ = qs_click_point(host.window, 12, 10)
        selection = .init(insertionPoint: text.range(of: "@Alice")!.upperBound)
        host.update()
        qs_flush()
        _ = qs_send_key_sequence(host.window, "Backspace")
        XCTAssertEqual(String(text.characters), "Hi !")
        XCTAssertEqual(selection.indices(in: text), .insertionPoint(text.index(text.startIndex, offsetByCharacters: 3)))
        _ = "x".withCString { qs_commit_text(host.window, $0, 1) }
        XCTAssertEqual(String(text.characters), "Hi x!")
    }

    @MainActor func testIncomingFormattingAndMultilineEdits() async {
        var text: AttributedString = "same\nsame"
        var selection = AttributedTextSelection()
        let host = Host(title: "Styles") { context in
            TextEditor(text: Binding(get: { text }, set: { text = $0 }),
                       selection: Binding(get: { selection }, set: { selection = $0 })).resolve(context)
        }
        defer { host.close() }
        host.open(width: 200, height: 96)
        _ = qs_click_point(host.window, 15, 11)
        let last = text.index(text.startIndex, offsetByCharacters: 5)
        text[last..<text.endIndex].font = .headline
        selection = .init(insertionPoint: text.endIndex)
        host.update()
        qs_flush()
        _ = qs_send_key_sequence(host.window, "Return")
        let input = "β"
        _ = input.withCString { qs_commit_text(host.window, $0, input.utf8.count) }
        XCTAssertEqual(String(text.characters), "same\nsame\nβ")
        XCTAssertNil(text.runs[text.startIndex].font)
        XCTAssertEqual(text.runs[text.index(beforeCharacter: text.endIndex)].font, .headline)
    }
}
