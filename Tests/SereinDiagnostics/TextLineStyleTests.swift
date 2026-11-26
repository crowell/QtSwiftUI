import SwiftUI
import XCTest

final class TextLineStyleTests: XCTestCase {
    @MainActor func testColoredSolidAndPatternedUnderlines() async throws {
        let red = Color(.sRGB, red: 1, green: 0, blue: 0)
        var run = AttributedString("MMMMMM")
        run.underlineStyle = Text.LineStyle(pattern: .dash, color: red)
        XCTAssertEqual(run.underlineStyle, .init(pattern: .dash, color: red))
        XCTAssertEqual(Text.LineStyle.single, .init(pattern: .solid))
        let solid: Text = Text("MMMMMM").underline(color: red)
        let screen = VStack(spacing: 0) {
            solid.frame(height: 32)
            Text(run).frame(height: 32)
            Text("MMMMMM").underline(false, pattern: .dot, color: red).frame(height: 32)
        }.font(.system(size: 18, design: .monospaced)).foregroundStyle(Color(.sRGB, red: 0, green: 0, blue: 1)).background(Color.white)
        let window = try await ScreenWindow(screen, width: 90, height: 96)
        defer { window.close() }
        func redColumns(_ top: Int) -> Int {
            (18..<72).filter { x in
                (top+17..<top+28).contains { y in
                    let pixel = window.pixel(x, y)
                    return pixel >> 16 > 165 && (pixel & 255) + 55 < pixel >> 16 && (pixel >> 8 & 255) + 55 < pixel >> 16
                }
            }.count
        }
        let solidWidth = redColumns(0), dashedWidth = redColumns(32)
        XCTAssertGreaterThan(solidWidth, 45)
        XCTAssertGreaterThan(dashedWidth, 8)
        XCTAssertLessThan(dashedWidth, solidWidth)
        XCTAssertEqual(redColumns(64), 0)
    }
}
