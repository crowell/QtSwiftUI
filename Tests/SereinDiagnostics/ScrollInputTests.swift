import XCTest
import SwiftUI

@MainActor @Observable private final class ScrollInputModel {
    var locked = true
    var offset: CGFloat = 0
    var taps = 0
}
private struct ScrollInputContent: View {
    var model: ScrollInputModel
    @Environment(\.isScrollEnabled) var enabled
    var body: some View {
        ScrollView {
            (enabled ? Color.black : Color.white)
                .frame(height: 500).onTapGesture { model.taps += 1 }
        }.onScrollGeometryChange(for: CGFloat.self) { $0.contentOffset.y } action: { _, offset in model.offset = offset }
    }
}
private struct LockedScroll: View {
    let model: ScrollInputModel
    var body: some View {
        VStack {
            ScrollInputContent(model: model).scrollDisabled(false)
        }.scrollDisabled(model.locked)
    }
}
final class ScrollInputTests: XCTestCase {
    @MainActor func testScrollLockPreservesTapsAndRespondsToUpdates() async throws {
        let model = ScrollInputModel()
        let window = try await ScreenWindow(LockedScroll(model: model), width: 100, height: 100)
        defer { window.close() }
        XCTAssertEqual(window.pixel(20, 20), 0xffffff)
        #if os(Linux)
        try await window.wheel(down: true)
        #else
        XCTAssertFalse(window.showsVerticalScroller)
        #endif
        XCTAssertEqual(model.offset, 0)
        try await window.click(20, 20)
        XCTAssertEqual(model.taps, 1)
        model.locked = false
        try await window.settle()
        XCTAssertEqual(window.pixel(20, 20), 0)
        #if os(Linux)
        try await window.wheel(down: true)
        #else
        XCTAssertTrue(window.showsVerticalScroller)
        try await window.scroll(toEnd: true)
        #endif
        XCTAssertGreaterThan(model.offset, 0)
    }
}
