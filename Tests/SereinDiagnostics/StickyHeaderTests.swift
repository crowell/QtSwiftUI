import XCTest
import SwiftUI
@testable import CallDiagnostics
#if os(Linux)
import QtBridge
@testable import SwiftUI
#else
import AppKit
#endif

final class StickyHeaderTests: XCTestCase {
    @MainActor func testOriginalDateHeaderSticksAboveScrolledContent() async throws {
        var positions: [CGFloat] = []
        let view = ScrollView {
            AxoChatDateSection.Root {
                AxoChatDateSection.Header("Today")
                    .onGeometryChange(for: CGFloat.self) { $0.frame(in: .scrollView).minY } action: { positions.append($0) }
                Color(white: 0.6).frame(height: 240)
            }
        }
        .scrollIndicators(.never)
        .frame(width: 180, height: 80)
        .background(Color.white)
        .environment(\.colorScheme, .light)
        #if os(Linux)
        let host = Host(title: "Date section") { view.resolve($0) }
        defer { host.close() }
        host.open(width: 180, height: 80)
        func sample(_ x: Int, _ y: Int) -> Int { Int(qs_pixel(host.window, Int32(x), Int32(y)) & 255) }
        func scroll() { XCTAssertEqual(qs_scroll_to_end(host.window), 1) }
        #else
        _ = NSApplication.shared
        let host = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 180, height: 80),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        defer { withExtendedLifetime(window) {} }
        func settle() {
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.08))
        }
        settle()
        func sample(_ x: Int, _ y: Int) -> Int {
            guard let image = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return -1 }
            host.cacheDisplay(in: host.bounds, to: image)
            return Int(((image.colorAt(x: x * image.pixelsWide / 180, y: y * image.pixelsHigh / 80)?.blueComponent ?? 0) * 255).rounded())
        }
        func scroll() {
            func find(_ view: NSView) -> NSScrollView? {
                if let scroll = view as? NSScrollView { return scroll }
                return view.subviews.lazy.compactMap { find($0) }.first
            }
            guard let scroll = find(host) else { XCTFail("Missing native scroll view"); return }
            scroll.contentView.scroll(to: CGPoint(x: 0, y: 204))
            scroll.reflectScrolledClipView(scroll.contentView)
            settle()
        }
        #endif
        XCTAssertGreaterThan(sample(5, 19), 220)
        scroll()
        let document = sample(5, 19)
        XCTAssertTrue((100...200).contains(document), "The gray document scrolled underneath the header")
        XCTAssertEqual(positions.first, 0)
        XCTAssertEqual(positions.last, -204)
        #if os(Linux)
        // NSView.cacheDisplay captures the document without the translated label.
        // Check the live Qt label here and the nested effect on both renderers in VisualEffectTests.
        let ink = (72...108).map { sample($0, 19) }
        XCTAssertLessThan(ink.min() ?? 255, document - 25)
        #endif
        XCTAssertEqual(sample(67, 19), document)
    }
}
