import XCTest
import SwiftUI
#if os(Linux)
@testable import SwiftUI
import QtBridge
#else
import AppKit
#endif

private func configureBounce<V: View>(_ view: V) -> some View {
    view.scrollBounceBehavior(.always, axes: .horizontal)
        .scrollBounceBehavior(.basedOnSize)
}

final class ScrollBounceTests: XCTestCase {
    @MainActor func testAxisPoliciesOnShortAndLongContent() async throws {
        for height in [40, 200] {
            let scroll = configureBounce(ScrollView([.horizontal, .vertical]) {
                Color.black.frame(width: 40, height: CGFloat(height))
            }.scrollIndicators(.hidden))
            let window = try await ScreenWindow(scroll, width: 100, height: 100)
            defer { window.close() }
            #if os(Linux)
            XCTAssertEqual(qs_can_overshoot(window.host.window, 1), 1)
            XCTAssertEqual(qs_can_overshoot(window.host.window, 0), height > 100 ? 1 : 0)
            #else
            func findScroll(in view: NSView) -> NSScrollView? {
                if let scroll = view as? NSScrollView { return scroll }
                return view.subviews.lazy.compactMap { findScroll(in: $0) }.first
            }
            let native = try XCTUnwrap(findScroll(in: window.hosting))
            XCTAssertEqual(native.horizontalScrollElasticity, .allowed)
            if height <= 100 {
                XCTAssertEqual(native.verticalScrollElasticity, .none)
            } else {
                let document = try XCTUnwrap(native.documentView)
                XCTAssertGreaterThan(document.bounds.height, native.contentView.bounds.height)
                native.contentView.scroll(to: CGPoint(x: 0, y: 50))
                XCTAssertEqual(native.contentView.bounds.origin.y, 50)
            }
            #endif
        }
    }
}
