import SwiftUI
import XCTest

final class CanvasTextTests: XCTestCase {
    @MainActor func testWrappingBaselinesAndPerRunInk() async throws {
        var first = AttributedString("Red")
        first.foregroundColor = Color(.sRGB, red: 1, green: 0, blue: 0)
        let font = Font.custom("Helvetica", fixedSize: 18)
        let screen = Canvas { context, _ in
            let text = context.resolve(Text(verbatim: "First line\nSecond line").font(font))
            let wide = CGSize(width: 180, height: 90)
            let baseline = text.firstBaseline(in: wide)
            XCTAssertGreaterThan(baseline, 5)
            let last = text.lastBaseline(in: wide), size = text.measure(in: wide)
            XCTAssertGreaterThan(last, baseline + 10)
            XCTAssertGreaterThan(size.height, last)
            let narrow = CGSize(width: 40, height: 180)
            let wrapped = text.measure(in: narrow)
            let clipped = text.lastBaseline(in: CGSize(width: 180, height: 1))
            XCTAssertLessThanOrEqual(wrapped.width, 40)
            XCTAssertGreaterThan(wrapped.height, size.height)
            XCTAssertEqual(clipped, baseline, accuracy: 1)
            var label = context.resolve(Text(first + AttributedString(" Blue")).font(font))
            label.shading = .color(Color(.sRGB, red: 0, green: 0, blue: 1))
            context.draw(label, at: CGPoint(x: 15, y: 10), anchor: .topLeading)
            context.draw(Text(verbatim: "Ink").font(font).foregroundColor(.black), in: CGRect(x: 20, y: 40, width: 80, height: 30))
        }.frame(width: 160, height: 80).background(.white)
        let window = try await ScreenWindow(screen, width: 160, height: 80)
        defer { window.close() }
        try window.capture("canvas-text.png", directoryVariable: "QTSWIFTUI_CANVAS_REFERENCE")
        var red = CGRect.null, blue = CGRect.null, black = CGRect.null
        for y in 0..<80 {
            for x in 0..<120 {
                let pixel = window.pixel(x, y)
                let r = (pixel >> 16) & 255, g = (pixel >> 8) & 255, b = pixel & 255
                let point = CGRect(x: x, y: y, width: 1, height: 1)
                if r > 160 && g < 90 && b < 90 { red = red.union(point) }
                if b > 160 && r < 90 && g < 90 { blue = blue.union(point) }
                if max(r, g, b) < 60 { black = black.union(point) }
            }
        }
        for ink in [red, blue, black] { XCTAssertFalse(ink.isNull); XCTAssertGreaterThan(ink.height, 5) }
        XCTAssertTrue(CGRect(x: 15, y: 10, width: 55, height: 29).contains(red), "\(red)")
        XCTAssertTrue(CGRect(x: 40, y: 10, width: 72, height: 29).contains(blue), "\(blue)")
        XCTAssertTrue(CGRect(x: 20, y: 40, width: 65, height: 30).contains(black), "\(black)")
    }
}
