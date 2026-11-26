import SwiftUI
import XCTest
#if os(Linux)
import QtBridge
@testable import SwiftUI
#endif

final class ContinuousHoverTests: XCTestCase {
    @MainActor func testHoverRegionsPreserveButtonGeometryAndInput() async throws {
        var local: [HoverPhase] = [], global: [HoverPhase] = [], named: [HoverPhase] = []
        var frame = CGRect.zero
        var taps = 0
        let view = Button { taps += 1 } label: { Color.blue.frame(width: 60, height: 30) }
            .buttonStyle(.plain)
            .onContinuousHover { local.append($0) }
            .onContinuousHover(coordinateSpace: GlobalCoordinateSpace()) { global.append($0) }
            .onContinuousHover(coordinateSpace: CoordinateSpace.named("area")) { named.append($0) }
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame = $0 }
            .padding(10).coordinateSpace(name: "area")
            .frame(width: 120, height: 80)
        let window = try await ScreenWindow(view, width: 120, height: 80)
        defer { window.close() }
        XCTAssertEqual(frame, CGRect(x: 30, y: 25, width: 60, height: 30))
        #if os(Linux)
        qs_move_pointer(window.host.window, 1, 1)
        local.removeAll()
        global.removeAll()
        named.removeAll()
        qs_move_pointer(window.host.window, 48, 31)
        qs_move_pointer(window.host.window, 58.5, 39.5)
        qs_move_pointer(window.host.window, 1, 1)
        XCTAssertEqual(local, [.active(.init(x: 18, y: 6)), .active(.init(x: 28.5, y: 14.5)), .ended])
        XCTAssertEqual(global, [.active(.init(x: 48, y: 31)), .active(.init(x: 58.5, y: 39.5)), .ended])
        XCTAssertEqual(named, [.active(.init(x: 28, y: 16)), .active(.init(x: 38.5, y: 24.5)), .ended])
        #endif
        try await window.click(48, 31)
        XCTAssertEqual(taps, 1)
    }
}
