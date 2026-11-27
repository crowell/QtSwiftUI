import SwiftUI
import XCTest
#if os(Linux)
@testable import SwiftUI
import QtBridge
import UniformTypeIdentifiers
#else
import AppKit
#endif

private struct PermitSelection: TextSelectability { static let allowsSelection = true }
private struct DenySelection: TextSelectability { static let allowsSelection = false }

final class TextSelectabilityTests: XCTestCase {
    func testBuiltInPolicies() {
        XCTAssertTrue(EnabledTextSelectability.allowsSelection)
        XCTAssertFalse(DisabledTextSelectability.allowsSelection)
    }

    @MainActor func testCustomPoliciesAndNearestOverrideForPlainAndAttributedText() async throws {
        let words = "Harbor ferry"
        for rich in [false, true] {
            let text = rich ? Text(AttributedString(words)) : Text(verbatim: words)
            let content = VStack(spacing: 0) {
                text.textSelection(PermitSelection()).frame(height: 30)
                text.textSelection(.enabled).frame(height: 30)
                text.textSelection(DenySelection()).frame(height: 30)
                text.frame(height: 30)
            }.font(.system(size: 18, design: .monospaced)).textSelection(.disabled)
            let screen = try await ScreenWindow(content, width: 240, height: 120, keyboard: true)
            defer { screen.close() }
            for (index, selectable) in [true, true, false, false].enumerated() {
                let y = 15 + 30 * index
                #if os(Linux)
                // Clear the previous selection before trying to copy from another row.
                try await screen.click(110, max(15, y - 30))
                try await screen.click(90, y)
                qs_clipboard_text("untouched")
                try await screen.drag(from: CGPoint(x: 90, y: y), to: CGPoint(x: 145, y: y))
                XCTAssertEqual(qs_send_key_sequence(screen.host.window, "Ctrl+C"), 1)
                let items = NSItemProvider.clipboardItems(qs_clipboard_contents(), matching: [UTType.plainText.identifier], includingData: true)
                let copied = try XCTUnwrap(items.first?.transferData(for: [.plainText]).first?.0)
                let selection = try XCTUnwrap(String(data: copied, encoding: .utf8))
                if selectable {
                    XCTAssertGreaterThan(selection.count, 2)
                    XCTAssertLessThan(selection.count, words.count)
                    XCTAssertTrue(words.contains(selection), "Row \(index), rich \(rich) copied \(selection)")
                } else {
                    XCTAssertEqual(selection, "untouched")
                }
                #else
                // macOS installs a native pointer interaction on the selectable glyphs.
                let point = try XCTUnwrap(screen.hosting.superview).convert(NSPoint(x: 120, y: 120 - y), from: nil)
                let hit = try XCTUnwrap(screen.hosting.hitTest(point))
                XCTAssertEqual(hit !== screen.hosting, selectable)
                #endif
            }
        }
    }
}
