import XCTest
import SwiftUI
#if os(Linux)
@testable import SwiftUI
import QtBridge
#else
import AppKit
#endif

private struct Slot: LayoutValueKey { static let defaultValue = -1 }
private struct SubsetLayout: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        CGSize(width: 100, height: 20)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let middle: LayoutSubviews = subviews[1..<3]
        let order: LayoutSubviews = subviews[[3,1,1,0]]
        XCTAssertEqual(middle.indices, 0..<2)
        XCTAssertEqual(middle, subviews[[1,2]])
        XCTAssertEqual(middle[0..<1], subviews[[1]])
        XCTAssertEqual(subviews[2..<2], subviews[3..<3])
        XCTAssertEqual(order.map { $0[Slot.self] }, [3,1,1,0])
        XCTAssertEqual(order[1], order[2])
        XCTAssertNotEqual(subviews, subviews[subviews.indices])
        var flipped = order
        flipped.layoutDirection = subviews.layoutDirection == .leftToRight ? .rightToLeft : .leftToRight
        XCTAssertNotEqual(flipped, order)
        XCTAssertNotEqual(flipped[0], order[0])
        for (i, item) in flipped[[0,1,3]].enumerated() {
            item.place(at: CGPoint(x: 10 + i*20, y: 5), proposal: .unspecified)
        }
    }
}

final class LayoutSubsetTests: XCTestCase {
    @MainActor func testMappedSubviewsKeepTraitsAndPlaceInParentDirection() async throws {
        for rtl in [false, true] {
            let view = SubsetLayout {
                ForEach(0..<4) { index in
                    Color.black.frame(width: CGFloat(index + 1) * 2, height: 10).layoutValue(key: Slot.self, value: index)
                }
            }.background(Color.white).environment(\.layoutDirection, rtl ? .rightToLeft : .leftToRight)
            #if os(Linux)
            let host = Host(title: "Layout subsets") { view.resolve($0) }
            defer { host.close() }
            host.open(width: 100, height: 20)
            func dark(_ x: Int) -> Bool { qs_pixel(host.window, Int32(x), 10) & 255 < 120 }
            #else
            let image = NSBitmapImageRep(cgImage: try XCTUnwrap(ImageRenderer(content: view).cgImage))
            func dark(_ x: Int) -> Bool { image.colorAt(x: x, y: 10)!.redComponent < 0.5 }
            #endif
            let darkPixels = (8..<92).filter { dark($0) }
            // SwiftUI centers the omitted six-point child in the layout.
            let expected = Array(10..<18) + Array(30..<34) + Array(47..<53)
            XCTAssertEqual(darkPixels, rtl ? expected.reversed().map { 99 - $0 } : expected)
        }
    }
}
