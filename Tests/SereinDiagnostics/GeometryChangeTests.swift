import XCTest
#if os(Linux)
import QtBridge
@testable import SwiftUI
#else
import AppKit
import SwiftUI
#endif

final class GeometryChangeTests: XCTestCase {
    @MainActor func testSizeAndNamedFrameAcrossLayoutPasses() async {
        var sizes: [CGSize] = []
        var frames: [[CGRect]] = []
        func view(_ width: CGFloat) -> some View {
            Color.clear.frame(width: width, height: 12)
                .onGeometryChange(for: CGSize.self) { $0.size } action: { sizes.append($0) }
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("panel")) } action: { frames.append([$0, $1]) }
                .padding(.leading, 7)
                .frame(width: 100, height: 60, alignment: .topLeading)
                .coordinateSpace(.named("panel"))
        }
        #if os(Linux)
        var width: CGFloat = 30
        let host = Host(title: "Geometry") { view(width).resolve($0) }
        defer { host.close() }
        host.open(width: 100, height: 60)
        func set(_ value: CGFloat) {
            width = value
            host.update()
            qs_flush()
        }
        #else
        _ = NSApplication.shared
        let host = NSHostingView(rootView: view(30))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 100, height: 60),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        defer { withExtendedLifetime(window) {} }
        func set(_ value: CGFloat) {
            host.rootView = view(value)
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
        }
        #endif
        set(30)
        set(50)
        set(50)
        let start = CGRect(x: 7, y: 0, width: 30, height: 12)
        let end = CGRect(x: 7, y: 0, width: 50, height: 12)
        XCTAssertEqual(sizes, [start.size, end.size])
        XCTAssertEqual(frames, [[start, start], [start, end]])
    }
}
