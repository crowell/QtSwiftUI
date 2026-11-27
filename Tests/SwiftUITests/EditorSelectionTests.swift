import QtBridge
import XCTest
@testable import SwiftUI

final class EditorSelectionTests: XCTestCase {
    func testValueSemanticsMatchTheNativeConstructors() {
        let text = "abc"
        let start = text.startIndex
        XCTAssertEqual(TextSelection(insertionPoint: start), TextSelection(range: start..<start))
        XCTAssertTrue(TextSelection(range: start..<start).isInsertion)
        let ranges = RangeSet(start..<text.endIndex)
        XCTAssertEqual(TextSelection(ranges: ranges).indices, .multiSelection(ranges))
        XCTAssertFalse(TextSelection(ranges: .init()).isInsertion)
        XCTAssertEqual(TextSelection(ranges: ranges).affinity, .automatic)
    }

    @MainActor func testClickThroughStrokeTransfersTextInputToTheEditor() async {
        var subject = "", message = ""
        let host = Host(title: "Feedback") { context in
            VStack(spacing: 0) {
                TextField("Subject", text: Binding(get: { subject }, set: { subject = $0 })).frame(height: 40)
                TextEditor(text: Binding(get: { message }, set: { message = $0 }))
                    .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(.gray, lineWidth: 1) }
            }.resolve(context)
        }
        defer { host.close() }
        host.open(width: 240, height: 140)
        _ = qs_click_point(host.window, 50, 20)
        XCTAssertEqual(qs_commit_text(host.window, "A", 1), 1)
        _ = qs_click_point(host.window, 50, 70)
        XCTAssertEqual(qs_commit_text(host.window, "B", 1), 1)
        XCTAssertEqual(subject, "A")
        XCTAssertEqual(message, "B")
    }

    @MainActor func testUnicodeRangeMovesBothWaysAndReplacesSelectedText() async {
        enum Control: CaseIterable { case editor, field, multilineField }
        for control in Control.allCases {
            var text = "A🎧 café"
            var selected: TextSelection?
            let content = Binding(get: { text }, set: { text = $0 })
            let selection = Binding(get: { selected }, set: { selected = $0 })
            let host = Host(title: "Composer") { context in
                Group {
                    switch control {
                    case .editor: TextEditor(text: content, selection: selection)
                    case .field: TextField("Message", text: content, selection: selection)
                    case .multilineField: TextField("Message", text: content, selection: selection, axis: .vertical)
                    }
                }.textSelectionAffinity(.upstream).resolve(context)
            }
            defer { host.close() }
            host.open(width: 250, height: 85)
            qs_flush()
            _ = qs_click_point(host.window, 30, 22)
            let emoji = text.range(of: "🎧")!
            selected = TextSelection(range: emoji)
            host.update()
            qs_flush()
            let replacement = "é🪴"
            XCTAssertEqual(replacement.withCString { qs_commit_text(host.window, $0, replacement.utf8.count) }, 1)
            XCTAssertEqual(text, "Aé🪴 café")
            XCTAssertEqual(selected?.indices, .selection(text.range(of: " ")!.lowerBound..<text.range(of: " ")!.lowerBound))
            XCTAssertEqual(selected?.affinity, .upstream)
            _ = qs_send_key_sequence(host.window, "Shift+Left")
            guard case .selection(let range) = selected?.indices else { return XCTFail("Selection missing for \(control)") }
            XCTAssertEqual(String(text[range]), "🪴")
        }
    }
}
