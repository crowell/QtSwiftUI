import SwiftUI
import XCTest

final class AttributedTextTests: XCTestCase {
    @MainActor func testLinkUsesItsOwnRunAndOpenURLHandler() async throws {
        let target = try XCTUnwrap(URL(string: "https://example.org/details?a=1&b=2"))
        let red = Color(.sRGB, red: 1, green: 0, blue: 0)
        let yellow = Color(.sRGB, red: 1, green: 1, blue: 0)
        var text = AttributedString("AAA ")
        var action = AttributedString("BBB")
        action.link = target
        action.font = .system(size: 20, design: .monospaced)
        action.backgroundColor = yellow
        action.foregroundColor = red
        text += action
        text += AttributedString(" <C>")
        var links: [URL] = []
        let screen = Text(text).font(.system(size: 20, design: .monospaced))
            .frame(width: 240, height: 60, alignment: .leading).background(Color.white)
            .environment(\.openURL, OpenURLAction { links.append($0); return .handled })
        let window = try await ScreenWindow(screen, width: 240, height: 60)
        defer { window.close() }
        let patch = (53...63).map { window.pixel($0, 30) }
        XCTAssertTrue(patch.contains(0xffff00), "The run has its yellow background")
        XCTAssertTrue(patch.contains { ($0 >> 16) > 220 && ($0 >> 8 & 255) < 100 && ($0 & 255) < 40 },
                      "The link uses the explicit red foreground")
        try await window.click(15, 30)
        try await window.click(110, 30)
        XCTAssertEqual(links, [])
        try await window.click(65, 30)
        XCTAssertEqual(links, [target])
    }
}
