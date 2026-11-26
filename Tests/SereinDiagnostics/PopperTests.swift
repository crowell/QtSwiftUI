import SwiftUI
import XCTest
@testable import CallDiagnostics
#if os(Linux)
import QtBridge
@testable import SwiftUI
#else
import AppKit
#endif

final class PopperTests: XCTestCase {
    @MainActor func testAnchoredLayerPlacementClipAndOutsideTap() async throws {
        var dismissed = 0
        let view = ZStack {
            Color.white
            Color.black.frame(width: 20, height: 12)
                .axoPopper(id: "details", isPresented: true, placement: .init(sideOffset: 4),
                           dismiss: { dismissed += 1 }) {
                    Color.black.frame(width: 16, height: 16).clipShape(Circle())
                }
        }.frame(width: 80, height: 80).axoLayerHost()
        #if os(Linux)
        let host = Host(title: "Floating layer") { view.resolve($0) }
        defer { host.close() }
        host.open(width: 80, height: 80)
        func blue(_ x: Int, _ y: Int) -> Int { Int(qs_pixel(host.window, Int32(x), Int32(y)) & 255) }
        #else
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 80, pixelsHigh: 80,
                                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                                     isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let graphics = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: bitmap))
        ImageRenderer(content: view).render { _, draw in draw(graphics.cgContext) }
        func blue(_ x: Int, _ y: Int) -> Int {
            Int(((bitmap.colorAt(x: x, y: y)?.blueComponent ?? 0) * 255).rounded())
        }
        #endif
        XCTAssertEqual(blue(40, 39), 0, "trigger")
        XCTAssertEqual(blue(40, 47), 255, "four-point gap")
        XCTAssertEqual(blue(40, 56), 0, "floating content")
        XCTAssertEqual(blue(32, 50), 255, "clipped corner")
        #if os(Linux)
        XCTAssertEqual(qs_click_point(host.window, 10, 12), 1)
        XCTAssertEqual(dismissed, 1)
        #endif
    }
}
