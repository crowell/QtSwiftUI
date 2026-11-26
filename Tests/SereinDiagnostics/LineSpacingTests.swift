import SwiftUI
import XCTest

final class LineSpacingTests: XCTestCase {
    @MainActor func testSpacingBetweenWrappedAndExplicitLines() async throws {
        XCTAssertEqual(EnvironmentValues().lineSpacing, 0)
        var sizes: [String: CGFloat] = [:]
        func sample(_ key: String, _ text: Text, gap: CGFloat, width: CGFloat = 140) -> some View {
            text.font(.system(size: 15, design: .monospaced))
                .fixedSize(horizontal: false, vertical: true)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { sizes[key] = $0 }
                .frame(width: width)
                .lineSpacing(gap)
        }
        func reserved(_ key: String, gap: CGFloat) -> some View {
            Text("X").font(.system(size: 15)).lineLimit(3, reservesSpace: true).lineSpacing(gap)
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { sizes[key] = $0 }
        }
        let view = VStack(spacing: 0) {
            reserved("reserved", gap: 0)
            reserved("reserved spaced", gap: 6)
            sample("single", Text("x"), gap: 0)
            sample("single spaced", Text("x"), gap: 6)
            sample("paragraphs", Text("A\nB\nC"), gap: 0)
            sample("paragraphs spaced", Text("A\nB\nC"), gap: 6)
            sample("wrapped", Text(AttributedString("one two three")), gap: 0, width: 55)
            sample("wrapped spaced", Text(AttributedString("one two three")), gap: 6, width: 55)
        }
        let window = try await ScreenWindow(view, width: 160, height: 540)
        defer { window.close() }
        try await window.settle()
        func difference(_ key: String) throws -> CGFloat {
            try XCTUnwrap(sizes[key + " spaced"]) - XCTUnwrap(sizes[key])
        }
        XCTAssertEqual(try difference("reserved"), 0, accuracy: 1)
        XCTAssertEqual(try difference("single"), 0, accuracy: 1)
        XCTAssertEqual(try difference("paragraphs"), 12, accuracy: 1)
        XCTAssertEqual(try difference("wrapped"), 12, accuracy: 1)
    }
}
