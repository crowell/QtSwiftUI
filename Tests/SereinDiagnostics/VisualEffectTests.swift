import SwiftUI
import XCTest
#if os(Linux)
import QtBridge
@testable import SwiftUI
#else
import AppKit
#endif

private struct Overlap: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for child in subviews { child.place(at: bounds.origin, proposal: ProposedViewSize(bounds.size)) }
    }
}

final class VisualEffectTests: XCTestCase {
    @MainActor func testDepthAndNestedGeometryDuringTranslation() async throws {
        let view = Overlap {
            Color.black.frame(width: 40, height: 20)
                .visualEffect { effect, proxy in
                    effect.opacity(proxy.frame(in: .named("stage")).minY >= 10 ? 0.5 : 0)
                }
                .visualEffect { effect, _ in effect.offset(y: 10) }
                .zIndex(1).padding(0)
            Color.white
        }
        .frame(width: 40, height: 40).coordinateSpace(.named("stage"))
        #if os(Linux)
        let host = Host(title: "Depth") { view.resolve($0) }
        defer { host.close() }
        host.open(width: 40, height: 40)
        func blue(_ y: Int) -> Int { Int(qs_pixel(host.window, 20, Int32(y)) & 255) }
        #else
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 40, pixelsHigh: 40,
                                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                                     isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let graphics = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: bitmap))
        ImageRenderer(content: view).render { _, draw in draw(graphics.cgContext) }
        func blue(_ y: Int) -> Int {
            Int(((bitmap.colorAt(x: 20, y: y)?.blueComponent ?? 0) * 255).rounded())
        }
        #endif
        XCTAssertEqual(blue(5), 255)
        XCTAssertEqual(Double(blue(15)), 128, accuracy: 2)
        XCTAssertEqual(blue(35), 255)
    }
}
