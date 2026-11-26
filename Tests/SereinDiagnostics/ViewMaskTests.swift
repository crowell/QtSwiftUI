import SwiftUI
import XCTest

private func halfMask<V: View, M: View>(_ content: V, leading: Bool, @ContentBuilder stencil: () -> M) -> some View {
    content.mask(alignment: leading ? .leading : .trailing, stencil)
}

@MainActor @Observable private final class MaskModel { var moved = false }

final class ViewMaskTests: XCTestCase {
    @MainActor func testMaskUsesAlphaAndAlignmentAcrossUpdates() async throws {
        let model = MaskModel()
        struct Sample: View {
            var model: MaskModel
            var body: some View {
                halfMask(Color.black, leading: model.moved) { Color.white.opacity(0.5).frame(width: 20) }.mask(Color.white).background(Color.white)
                    .onTapGesture { model.moved.toggle() }
            }
        }
        let window = try await ScreenWindow(Sample(model: model), width: 60, height: 40)
        defer { window.close() }
        func shade(_ x: Int) -> UInt32 { window.pixel(x, 20) & 255 }
        XCTAssertEqual(shade(10), 255)
        XCTAssertTrue((110...200).contains(shade(50)))
        try await window.click(50, 20)
        XCTAssertTrue(model.moved)
        XCTAssertEqual(shade(50), 255)
        XCTAssertTrue((110...200).contains(shade(10)))
    }

    @MainActor func testHiddenKeepsSpaceAndSuppressesInput() async throws {
        var activations = 0
        var backgroundTaps = 0
        let view = HStack(spacing: 0) {
            Color.black.frame(width: 20)
            Group {
                Color.black.frame(width: 8)
                Color.black.frame(width: 12).onTapGesture { activations += 1 }
            }.hidden()
            Color.black.frame(width: 20).onTapGesture { activations += 1 }
        }.background(Color.white.onTapGesture { backgroundTaps += 1 })
        let window = try await ScreenWindow(view, width: 60, height: 40)
        defer { window.close() }
        XCTAssertEqual(window.pixel(10, 20), 0)
        XCTAssertEqual(window.pixel(30, 20), 0xffffff)
        XCTAssertEqual(window.pixel(50, 20), 0)
        try await window.click(30, 20)
        XCTAssertEqual(activations, 0)
        XCTAssertEqual(backgroundTaps, 1)
        try await window.click(50, 20)
        XCTAssertEqual(activations, 1)
    }
}
