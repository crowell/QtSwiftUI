import XCTest
import SwiftUI
#if os(Linux)
import QtBridge
@testable import SwiftUI
#else
import AppKit
#endif

final class SpatialTapTests: XCTestCase {
    @MainActor func testInputKindMasks() async {
        let kinds: [GestureInputKinds] = [.directTouch, .indirectTouch, .pencil, .pointer]
        XCTAssertEqual(kinds.map(\.rawValue), [1, 2, 4, 8])
        XCTAssertEqual(GestureInputKinds.all.rawValue, 127)
        #if os(Linux)
        for allowed: GestureInputKinds in [[], [.pencil, .pointer], [.directTouch, .indirectTouch], .all] {
            var taps = 0
            let view = Color.blue.frame(width: 40, height: 40)
                .onTapGesture(count: 2, inputKinds: allowed) { _ in taps += 1 }
            let host = Host(title: "Tap kinds") { view.resolve($0) }
            host.open(width: 40, height: 40)
            defer { host.close() }
            if allowed == .all {
                _ = qs_click_device(host.window, 20, 20, Int32(GestureInputKinds.pencil.rawValue))
                _ = qs_click_device(host.window, 20, 20, Int32(GestureInputKinds.pointer.rawValue))
                XCTAssertEqual(taps, 0, "Two distinct input devices do not make a double tap")
                _ = qs_click_device(host.window, 20, 20, Int32(GestureInputKinds.pointer.rawValue))
                XCTAssertEqual(taps, 1)
            }
            for kind in kinds {
                let before = taps
                XCTAssertEqual(qs_click_device(host.window, 20, 20, Int32(kind.rawValue)), 1)
                XCTAssertEqual(taps, before)
                XCTAssertEqual(qs_click_device(host.window, 20, 20, Int32(kind.rawValue)), 1)
                XCTAssertEqual(taps, before + (allowed.contains(kind) ? 1 : 0))
            }
        }
        #endif
    }

    @MainActor func testLocationInNestedCoordinateSpaces() async throws {
        XCTAssertEqual(SpatialTapGesture().count, 1)
        XCTAssertEqual(SpatialTapGesture(count: 2, coordinateSpace: .global).coordinateSpace, .global)
        for space: CoordinateSpace in [.local, .global, .named("wave")] {
            var taps: [CGPoint] = []
            let view = Color.blue.frame(width: 60, height: 30)
                .onTapGesture(coordinateSpace: space) { taps.append($0) }
                .padding(10).coordinateSpace(name: "wave").frame(width: 120, height: 80)
            #if os(Linux)
            let host = Host(title: "Samples") { view.resolve($0) }
            host.open(width: 120, height: 80)
            defer { host.close() }
            XCTAssertEqual(qs_click_point(host.window, 48, 31), 1)
            #else
            let hosting = NSHostingView(rootView: view)
            let window = NSWindow(contentRect: .init(x: 160, y: 160, width: 120, height: 80), styleMask: [.borderless],
                                  backing: .buffered, defer: false)
            window.contentView = hosting
            window.orderFrontRegardless()
            defer { window.orderOut(nil) }
            hosting.layoutSubtreeIfNeeded()
            for type: NSEvent.EventType in [.leftMouseDown, .leftMouseUp] {
                let event = try XCTUnwrap(NSEvent.mouseEvent(with: type, location: .init(x: 48, y: 49), modifierFlags: [],
                    timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber, context: nil,
                    eventNumber: type == .leftMouseDown ? 1 : 2, clickCount: 1, pressure: type == .leftMouseDown ? 1 : 0))
                window.sendEvent(event)
            }
            #endif
            XCTAssertEqual(taps, [space.isGlobal ? .init(x: 48, y: 31) : space.isLocal ? .init(x: 18, y: 6) : .init(x: 28, y: 16)])
        }
    }
}
