import XCTest
#if os(Linux)
import QtBridge
@testable import SwiftUI
#else
import SwiftUI
#endif

private struct DoubleTap: Gesture {
    var body: some Gesture<Void> { TapGesture(count: 2) }
}

final class GestureTests: XCTestCase {
    @MainActor func testGestureMaskAndComposedDoubleTap() async {
        XCTAssertEqual(GestureMask.none.rawValue, 0)
        XCTAssertEqual(GestureMask.gesture.union(.subviews), .all)
        XCTAssertEqual(TapGesture().count, 1)
        for mask: GestureMask in [.none, .gesture, .subviews, .all] {
            var inner = 0, outer = 0
            let view = Color.red.frame(width: 100, height: 60)
                .gesture(DoubleTap().onEnded { inner += 1 })
                .gesture(TapGesture().onEnded { outer += 1 }, including: mask)
            #if os(Linux)
            let host = Host(title: "Gestures") { view.resolve($0) }
            host.open(width: 100, height: 60)
            defer { host.close() }
            _ = qs_click_point(host.window, 50, 30)
            _ = qs_click_point(host.window, 50, 30)
            XCTAssertEqual(inner, mask.contains(.subviews) ? 1 : 0)
            XCTAssertEqual(outer, mask == .gesture ? 2 : 0)
            #endif
        }
    }

    #if os(Linux)
    @MainActor func testCombinedAccessibilityActions() async {
        var presses = 0
        let view = VStack {
            Text("Settings")
            Text("Decoration").accessibilityHidden(true)
            Button("Open") { presses += 1 }
        }.accessibilityElement(children: .combine)
        let host = Host(title: "Accessibility") { view.resolve($0) }
        host.open(width: 200, height: 100)
        defer { host.close() }
        XCTAssertEqual(qs_accessible_element(host.window, "Settings, Open", 0, "Press"), 1)
        XCTAssertEqual(presses, 1)
    }
    #endif
}
