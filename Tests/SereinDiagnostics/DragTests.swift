import XCTest
import SwiftUI
#if os(Linux)
import QtBridge
@testable import SwiftUI
#else
import AppKit
#endif

final class DragTests: XCTestCase {
    @MainActor func testDistanceAndCoordinateSpace() async throws {
        XCTAssertEqual(DragGesture().minimumDistance, 10)
        for space: CoordinateSpace in [.local, .global, .named("track")] {
            var changes: [DragGesture.Value] = []
            var endings: [DragGesture.Value] = []
            let gesture = DragGesture(minimumDistance: 10, coordinateSpace: space)
                .onChanged { changes.append($0) }.onEnded { endings.append($0) }
            let view = Color.blue.frame(width: 50, height: 30).gesture(gesture)
                .padding(10).coordinateSpace(name: "track")
                .frame(width: 140, height: 80)
            #if os(Linux)
            let host = Host(title: "Drag locations") { view.resolve($0) }
            host.open(width: 140, height: 80)
            defer { host.close() }
            XCTAssertEqual(qs_drag_pointer(host.window, 49, 31, 55, 31, 3), 1)
            XCTAssertTrue(changes.isEmpty)
            XCTAssertTrue(endings.isEmpty)
            XCTAssertEqual(qs_drag_pointer(host.window, 49, 31, 109, 31, 6), 1)
            #else
            let hosting = NSHostingView(rootView: view)
            let window = NSWindow(contentRect: CGRect(x: 160, y: 160, width: 140, height: 80),
                                  styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = hosting
            window.orderFrontRegardless()
            defer { window.orderOut(nil) }
            hosting.layoutSubtreeIfNeeded()
            func mouse(_ type: NSEvent.EventType, x: CGFloat, number: Int) throws {
                let event = try XCTUnwrap(NSEvent.mouseEvent(with: type, location: .init(x: x, y: 49),
                    modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                    context: nil, eventNumber: number, clickCount: 1, pressure: type == .leftMouseUp ? 0 : 1))
                window.sendEvent(event)
            }
            try mouse(.leftMouseDown, x: 49, number: 1)
            for index in 1...6 { try mouse(.leftMouseDragged, x: CGFloat(49 + 10 * index), number: index + 1) }
            try mouse(.leftMouseUp, x: 109, number: 8)
            #endif
            XCTAssertFalse(changes.isEmpty)
            XCTAssertEqual(endings.count, 1)
            let value = try XCTUnwrap(endings.first)
            let origin: CGPoint = space.isLocal ? .init(x: 45, y: 25) : space.isGlobal ? .zero : .init(x: 35, y: 15)
            XCTAssertEqual(value.startLocation, CGPoint(x: 49 - origin.x, y: 31 - origin.y))
            XCTAssertEqual(value.location, CGPoint(x: 109 - origin.x, y: 31 - origin.y))
            XCTAssertEqual(value.translation, CGSize(width: 60, height: 0))
            XCTAssertEqual(value.predictedEndTranslation.width, value.predictedEndLocation.x - value.startLocation.x, accuracy: 0.001)
            XCTAssertEqual(value.velocity.width, (value.predictedEndLocation.x - value.location.x) * 4, accuracy: 0.001)
        }
    }
}
