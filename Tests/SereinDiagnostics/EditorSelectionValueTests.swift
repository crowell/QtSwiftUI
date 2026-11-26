import Foundation
import SwiftUI
import XCTest

final class EditorSelectionValueTests: XCTestCase {
    func testAttributedRangesReplaceTogetherAndRetainTheNewSelection() {
        var text: AttributedString = "abcd"
        text[text.startIndex..<text.index(text.startIndex, offsetByCharacters: 2)].foregroundColor = .red
        text[text.index(text.startIndex, offsetByCharacters: 2)..<text.endIndex].foregroundColor = .green
        func point(_ n: Int) -> AttributedString.Index { text.index(text.startIndex, offsetByCharacters: n) }
        let ranges = RangeSet([point(0)..<point(1), point(2)..<point(3)])
        var selection = AttributedTextSelection(ranges: ranges)
        XCTAssertEqual(String(AttributedString(text[selection]).characters), "ac")
        XCTAssertEqual(selection.attributes(in: text).map(\.foregroundColor), [.red, .green])
        XCTAssertEqual(AttributedTextSelection(insertionPoint: point(2)).typingAttributes(in: text).foregroundColor, .red)
        text.replaceSelection(&selection, withCharacters: "★")
        XCTAssertEqual(String(text.characters), "★bd")
        XCTAssertEqual(String(AttributedString(text[selection]).characters), "★")
        XCTAssertEqual(selection.typingAttributes(in: text).foregroundColor, .red)
        text.transformAttributes(in: &selection) { $0.foregroundColor = .blue }
        XCTAssertEqual(Array(selection.attributes(in: text)[\.foregroundColor]), [.blue])
        XCTAssertEqual(text.runs[text.startIndex].foregroundColor, .blue)
    }

    func testInsertionTypingAttributesAndStaleIndices() {
        var text: AttributedString = "a🎉d"
        var selection = AttributedTextSelection()
        XCTAssertEqual(selection.indices(in: text), .insertionPoint(text.endIndex))
        selection = .init(insertionPoint: text.index(afterCharacter: text.startIndex))
        text.transformAttributes(in: &selection) { $0.foregroundColor = .red }
        XCTAssertNil(text.foregroundColor)
        text.replaceSelection(&selection, withCharacters: "é")
        XCTAssertEqual(String(text.characters), "aé🎉d")
        let end = text.index(text.startIndex, offsetByCharacters: 2)
        XCTAssertEqual(selection.indices(in: text), .insertionPoint(end))
        XCTAssertEqual(text.runs[text.index(afterCharacter: text.startIndex)].foregroundColor, .red)
        text.append(AttributedString("!"))
        XCTAssertEqual(selection.indices(in: text), .insertionPoint(text.endIndex))
    }
}
