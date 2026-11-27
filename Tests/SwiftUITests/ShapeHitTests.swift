import XCTest
#if os(Linux)
import QtBridge
@testable import SwiftUI
#else
import AppKit
import SwiftUI
#endif

final class ShapeHitTests: XCTestCase {
    @MainActor func testFrontmostPaintedShapeReceivesPointerInput() async throws {
        func check<Overlay: View>(_ name: String, center: Int, corner: Int, @ViewBuilder overlay: () -> Overlay) async throws {
            var clicks = 0
            let content = ZStack {
                Button { clicks += 1 } label: { Rectangle().fill(.blue) }.buttonStyle(.plain)
                overlay()
            }.frame(width: 160, height: 120)
            #if os(Linux)
            let host = Host(title: name) { content.resolve($0) }
            defer { host.close() }
            host.open(width: 160, height: 120)
            func click(_ x: Int, _ y: Int) throws {
                XCTAssertEqual(qs_click_point(host.window, Int32(x), Int32(y)), 1)
            }
            #else
            let hosting = NSHostingView(rootView: content)
            let window = NSWindow(contentRect: CGRect(x: 100, y: 100, width: 160, height: 120),
                                  styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = hosting
            window.orderFrontRegardless()
            defer { window.orderOut(nil) }
            hosting.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(50))
            func click(_ x: Int, _ y: Int) throws {
                for type: NSEvent.EventType in [.leftMouseDown, .leftMouseUp] {
                    let event = try XCTUnwrap(NSEvent.mouseEvent(with: type, location: CGPoint(x: x, y: 120 - y),
                        modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                        context: nil, eventNumber: 1, clickCount: 1, pressure: 1))
                    window.sendEvent(event)
                }
            }
            #endif
            try click(80, 60)
            XCTAssertEqual(clicks, center, name)
            try click(29, 8)
            XCTAssertEqual(clicks, center + corner, name)
        }
        try await check("Backdrop", center: 0, corner: 0) { Rectangle().fill(Color.black.opacity(0.25)) }
        try await check("Clear", center: 1, corner: 1) { Color.clear }
        try await check("Pass through", center: 1, corner: 1) { Rectangle().fill(.red).allowsHitTesting(false) }
        try await check("Circle", center: 0, corner: 1) { Circle().fill(.red) }
        try await check("Clear rectangle", center: 1, corner: 1) { Rectangle().fill(.clear) }
        try await check("Nearly transparent", center: 0, corner: 0) { Rectangle().fill(Color.black.opacity(0.001)) }
        try await check("Stroke interior", center: 1, corner: 1) { Rectangle().stroke(.black, lineWidth: 2) }
        try await check("Invisible group", center: 1, corner: 1) { Rectangle().fill(.red).opacity(0) }
        try await check("Grouped circle", center: 0, corner: 1) { Circle().fill(.red).padding(2).opacity(0.9) }
        try await check("Transparent gradient", center: 1, corner: 1) {
            LinearGradient(colors: [.clear, .clear], startPoint: .leading, endPoint: .trailing)
        }
        try await check("Partially transparent gradient", center: 0, corner: 0) {
            Rectangle().fill(LinearGradient(stops: [.init(color: .clear, location: 0.6), .init(color: .red, location: 0.61)],
                                            startPoint: .leading, endPoint: .trailing))
        }
        try await check("Gradient circle", center: 0, corner: 1) {
            Circle().fill(LinearGradient(colors: [.blue, .red], startPoint: .top, endPoint: .bottom))
        }
    }
}
