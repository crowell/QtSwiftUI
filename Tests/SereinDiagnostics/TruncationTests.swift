import SwiftUI
import XCTest

final class TruncationTests: XCTestCase {
    @MainActor func testExplicitNewlineAndDefaultTruncation() async throws {
        XCTAssertEqual(EnvironmentValues().truncationMode, .tail)
        let modes: [Text.TruncationMode] = [.head, .middle, .tail]
        for (rich, mode) in [false, true].flatMap({ rich in modes.map { (rich, $0) } }) {
            let actual = rich ? Text(AttributedString("AAAA\nBBBB")) : Text(verbatim: "AAAA\nBBBB")
            let expected = mode == .tail ? "AAAA…" : "AAAA"
            let reference = rich ? Text(AttributedString(expected)) : Text(verbatim: expected)
            let view = VStack(alignment: .leading, spacing: 0) {
                actual.lineLimit(1).truncationMode(mode)
                    .frame(width: 90, height: 26, alignment: .leading)
                reference
                    .frame(width: 90, height: 26, alignment: .leading)
            }.font(.system(size: 16, design: .monospaced)).foregroundStyle(Color.black).background(Color.white)
            let window = try await ScreenWindow(view, width: 90, height: 52)
            defer { window.close() }
            try window.capture("newline-\(mode).png", directoryVariable: "QTSWIFTUI_TEXT_REFERENCE")
            var ink = 0, mismatches = 0
            for y in stride(from: 6, through: 22, by: 2) {
                for x in stride(from: 1, through: 67, by: 3) {
                    let actual = window.pixel(x, y) & 0xff, expected = window.pixel(x, y + 26) & 0xff
                    if expected < 160 { ink += 1 }
                    if abs(Int(actual) - Int(expected)) > 16 { mismatches += 1 }
                }
            }
            XCTAssertGreaterThan(ink, 8)
            XCTAssertLessThanOrEqual(mismatches, 2, "Explicit paragraph break in \(mode) mode, attributed = \(rich)")
        }
    }

    @MainActor func testElidedAttributedTextRetainsVisibleStylesAndLinkTargets() async throws {
        let start = try XCTUnwrap(URL(string: "https://example.org/start"))
        let end = try XCTUnwrap(URL(string: "https://example.org/end"))
        var first = AttributedString(String(repeating: "A", count: 32))
        first.backgroundColor = .yellow
        first.link = start
        var last = AttributedString(String(repeating: "Z", count: 32))
        last.backgroundColor = .green
        last.link = end
        for limit in [1, 2] {
            for mode in [Text.TruncationMode.head, .middle, .tail] {
                var links: [URL] = []
                let view = Text(first + last).font(.system(size: 16, design: .monospaced))
                    .lineLimit(limit).truncationMode(mode)
                    .frame(width: 140, height: 60, alignment: .leading).background(Color.white)
                    .environment(\.openURL, OpenURLAction { links.append($0); return .handled })
                let window = try await ScreenWindow(view, width: 140, height: 60)
                defer { window.close() }
                try window.capture("trunc-\(limit)-\(mode).png", directoryVariable: "QTSWIFTUI_TEXT_REFERENCE")
                let y = limit == 1 ? 30 : 39
                let left = mode == .head ? end : start, right = mode == .tail ? start : end
                // Sample behind the glyphs to check which formatted ranges reached the last line.
                func showsStart(_ xs: ClosedRange<Int>) -> Bool {
                    xs.contains { x in
                        let pixel = window.pixel(x, y)
                        return pixel >> 16 > 210 && (pixel >> 8 & 255) > 150 && (pixel & 255) < 64
                    }
                }
                XCTAssertEqual(showsStart(20...25), left == start)
                XCTAssertEqual(showsStart(113...119), right == start)
                if limit == 1 {
                    try await window.click(22, y)
                    try await window.click(115, y)
                    XCTAssertEqual(links, [left, right])
                } else {
                    try await window.click(22, 20)
                    XCTAssertEqual(links, [start])
                }
            }
        }
    }
}
