import XCTest
@_spi(Qt) import SwiftUI

final class QtTextLayoutTests: XCTestCase {
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
