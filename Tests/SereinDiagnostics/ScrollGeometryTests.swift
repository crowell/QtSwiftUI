import XCTest
#if os(Linux)
import QtBridge
@testable import SwiftUI
#else
import AppKit
import SwiftUI
#endif

final class ScrollGeometryTests: XCTestCase {
    func testOffsetAndContainerMutation() {
        var geometry = ScrollGeometry(contentOffset: CGPoint(x: -10, y: 4), contentSize: CGSize(width: 80, height: 63),
                                      contentInsets: EdgeInsets(top: 3, leading: 7, bottom: 9, trailing: 11),
                                      containerSize: CGSize(width: 101, height: 52))
        XCTAssertEqual(geometry.visibleRect, CGRect(x: -10, y: 4, width: 101, height: 52))
        geometry.contentOffset.y = 18
        geometry.containerSize.width += 50
        geometry.contentInsets.top += 7
        XCTAssertEqual(geometry.bounds, CGRect(x: -10, y: 18, width: 151, height: 52))
        XCTAssertEqual(geometry.visibleRect, geometry.bounds)
    }

    @MainActor func testNativeScrollDeliversFilteredChanges() async throws {
        var contentPositions: [CGFloat] = []
        var thresholds: [[Bool]] = []
        var snapshots: [ScrollGeometry] = []
        let view = ScrollView {
            Color.black.frame(width: 50, height: 240)
                .onGeometryChange(for: CGFloat.self) { $0.frame(in: .scrollView(axis: .vertical)).minY } action: {
                    contentPositions.append($0)
                }
        }
        .scrollIndicators(.never)
        .onScrollGeometryChange(for: ScrollGeometry.self) { $0 } action: { _, next in snapshots.append(next) }
        .onScrollGeometryChange(for: Bool.self) { $0.contentOffset.y > 40 } action: { thresholds.append([$0, $1]) }
        .frame(width: 100, height: 80)

        #if os(Linux)
        let host = Host(title: "Scroll geometry") { view.resolve($0) }
        host.open(width: 100, height: 80)
        defer { host.close() }
        XCTAssertEqual(qs_scroll_to_end(host.window), 1)
        host.update()
        qs_flush()
        #else
        _ = NSApplication.shared
        let host = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 100, height: 80),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        defer { withExtendedLifetime(window) {} }
        func layout() {
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.06))
        }
        layout()
        func scrollView(in parent: NSView) -> NSScrollView? {
            if let scroll = parent as? NSScrollView { return scroll }
            return parent.subviews.lazy.compactMap { scrollView(in: $0) }.first
        }
        let scroll = try XCTUnwrap(scrollView(in: host))
        scroll.contentView.scroll(to: CGPoint(x: 0, y: 160))
        scroll.reflectScrolledClipView(scroll.contentView)
        layout()
        #endif
        XCTAssertEqual(contentPositions, [0, -160])
        XCTAssertEqual(thresholds, [[false, false], [false, true]])
        let last = try XCTUnwrap(snapshots.last)
        XCTAssertEqual(last.contentOffset.y, 160)
        XCTAssertEqual(last.contentSize.height, 240)
        XCTAssertEqual(last.contentSize.width, 50)
        XCTAssertEqual(last.containerSize, CGSize(width: 50, height: 80))
        XCTAssertEqual(last.visibleRect.minY, 160)
    }
}
