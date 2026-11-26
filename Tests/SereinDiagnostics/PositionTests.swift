import XCTest
import SwiftUI
#if os(Linux)
@testable import SwiftUI
import QtBridge
#else
import AppKit
#endif

private struct PositionProbe: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let child = subviews[0]
        XCTAssertEqual(child.sizeThatFits(.unspecified), CGSize(width: 8, height: 6))
        XCTAssertEqual(child.sizeThatFits(.init(width: 50, height: nil)), CGSize(width: 50, height: 6))
        XCTAssertEqual(child.sizeThatFits(.init(width: nil, height: 40)), CGSize(width: 8, height: 40))
        XCTAssertEqual(child.sizeThatFits(.zero), .zero)
        return CGSize(width: 60, height: 40)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews[0].place(at: bounds.origin, proposal: ProposedViewSize(bounds.size))
    }
}

final class PositionTests: XCTestCase {
    @MainActor func testProposalsAndMirroredCenter() async throws {
        for rtl in [false, true] {
            let view = PositionProbe { Color.black.frame(width: 8, height: 6).position(CGPoint(x: 18, y: 12)) }
                .frame(width: 60, height: 40).background(Color.white)
                .environment(\.layoutDirection, rtl ? .rightToLeft : .leftToRight)
            #if os(Linux)
            let host = Host(title: "Position") { view.resolve($0) }
            defer { host.close() }
            host.open(width: 60, height: 40)
            func ink(_ x: Int, _ y: Int) -> Bool { qs_pixel(host.window, Int32(x), Int32(y)) & 255 < 120 }
            #else
            let bitmap = NSBitmapImageRep(cgImage: try XCTUnwrap(ImageRenderer(content: view).cgImage))
            func ink(_ x: Int, _ y: Int) -> Bool { bitmap.colorAt(x: x, y: y)!.redComponent < 0.5 }
            #endif
            let middle = rtl ? 42 : 18
            XCTAssertEqual((0..<60).filter { ink($0,12) }, Array(middle-4..<middle+4))
            XCTAssertEqual((0..<40).filter { ink(middle,$0) }, Array(9..<15))
        }
    }

    @MainActor func testPositionedSiblingTapAndDragTargets() async throws {
        var taps: [Int] = [], drags: [Int] = [], locations: [CGPoint] = []
        let view = ZStack {
            ForEach([30, 130], id: \.self) { x in
                Circle().fill(Color.black).frame(width: 34, height: 34)
                    .contentShape(Circle()).position(x: CGFloat(x), y: 40)
                    .gesture(DragGesture(coordinateSpace: .named("board")).onEnded { value in
                        drags.append(x)
                        locations.append(value.location)
                    })
                    .onTapGesture { taps.append(x) }
            }
        }.coordinateSpace(.named("board")).frame(width: 160, height: 80)
        #if os(Linux)
        let host = Host(title: "Handles") { view.resolve($0) }
        defer { host.close() }
        host.open(width: 160, height: 80)
        func click(_ x: Int) { _ = qs_click_point(host.window, Int32(x), 40) }
        func drag(_ x: Int, _ end: Int) { _ = qs_drag_pointer(host.window, Int32(x), 40, Int32(end), 40, 5) }
        #else
        let hosting = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: CGRect(x: 160, y: 160, width: 160, height: 80),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }
        hosting.layoutSubtreeIfNeeded()
        var tick = 0
        func mouse(_ type: NSEvent.EventType, _ x: Int) {
            tick += 1
            let event = NSEvent.mouseEvent(with: type, location: CGPoint(x: x, y: 40), modifierFlags: [],
                                          timestamp: ProcessInfo.processInfo.systemUptime + Double(tick)*0.016,
                                          windowNumber: window.windowNumber, context: nil, eventNumber: tick, clickCount: 1, pressure: 1)!
            window.sendEvent(event)
        }
        func click(_ x: Int) { mouse(.leftMouseDown, x); mouse(.leftMouseUp, x) }
        func drag(_ x: Int, _ end: Int) {
            mouse(.leftMouseDown, x)
            for i in 1...5 { mouse(.leftMouseDragged, x + (end-x)*i/5) }
            mouse(.leftMouseUp, end)
        }
        #endif
        click(130)
        click(30)
        click(80)
        drag(30, 100)
        drag(130, 70)
        XCTAssertEqual(taps, [130,30])
        XCTAssertEqual(drags, [30,130])
        XCTAssertEqual(locations, [CGPoint(x: 100, y: 40),CGPoint(x: 70, y: 40)])
    }
}
