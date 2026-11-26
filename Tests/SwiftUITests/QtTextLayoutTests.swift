import XCTest
@_spi(Qt) import SwiftUI

final class QtTextLayoutTests: XCTestCase {
    @MainActor func testInlinePaddingReservesWidthAndWrapsAsOneWord() async throws {
        let font = Font.system(size: 16)
        let prefix = AttributedString("message\u{200b}")
        var padding = AttributedString("\u{00a0}\u{00a0}")
        let space = try XCTUnwrap(QtTextLayout.lines(in: "\u{00a0}", font: font).first?.advance)
        padding.kern = 18 - space
        let natural = try XCTUnwrap(QtTextLayout.lines(in: prefix, font: font).first?.advance)
        let full = QtTextLayout.lines(in: prefix + padding, font: font)
        XCTAssertEqual(try XCTUnwrap(full.first?.advance), natural + 36, accuracy: 0.1)
        let wrapped = QtTextLayout.lines(in: prefix + padding, font: font, width: natural + 35)
        XCTAssertEqual(wrapped.count, 2)
        XCTAssertEqual(try XCTUnwrap(wrapped.last?.width), 36, accuracy: 0.1)
        padding.tracking = 4
        let tracked = try XCTUnwrap(QtTextLayout.lines(in: padding, font: font).first?.advance)
        XCTAssertEqual(tracked, 2 * (space + 4), accuracy: 0.1)
    }

    @MainActor func testRunFontsParagraphsAndWordWrapping() async {
        let font = Font.system(size: 14)
        var word = AttributedString("ferry")
        word.font = .system(size: 30)
        let text = AttributedString("A🌲\n") + word + AttributedString(" crew")
        let lines = QtTextLayout.lines(in: text, font: font)
        XCTAssertEqual(lines.map(\.range), [NSRange(location: 0, length: 3), NSRange(location: 4, length: 10)])
        XCTAssertGreaterThan(lines[1].height, lines[0].height)
        let wrapped = QtTextLayout.lines(in: text, font: font, width: 24)
        XCTAssertEqual(wrapped.count, 3)
        let broken = QtTextLayout.lines(in: text, font: font, width: 24, breaksLongWords: true)
        XCTAssertGreaterThan(broken.count, wrapped.count)
        XCTAssertTrue(QtTextLayout.lines(in: "", font: font).isEmpty)
        let crlf = QtTextLayout.lines(in: "A\r\n\r\nB", font: font)
        XCTAssertEqual(crlf.map(\.range), [NSRange(location: 0, length: 1), NSRange(location: 3, length: 0), NSRange(location: 5, length: 1)])
    }
}
