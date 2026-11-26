import SwiftUI
import XCTest
@testable import CallDiagnostics
#if os(Linux)
import QtBridge
@testable import SwiftUI
#else
import AppKit
#endif

private struct ShadowFixture: View {
    var body: some View {
        ZStack {
            Color.white
            Rectangle().fill(Color.black)
                .frame(width: 40, height: 24)
                .cssBoxShadow([AxoShadowLayer(inset: false, x: 0, y: 4, blur: 8, spread: 0,
                                              color: RGBA(0, 0, 0, 0.8))], in: Rectangle())
        }
        .frame(width: 100, height: 80)
    }
}

final class ShadowTests: XCTestCase {
    @MainActor func testProductionBoxShadow() async throws {
        // Take samples from the black rectangle through the bottom of the shadow.
        let rows = [40, 52, 55, 58, 62, 70]
        #if os(Linux)
        let host = Host(title: "Shadow") { ShadowFixture().resolve($0) }
        defer { host.close() }
        host.open(width: 100, height: 80)
        let samples = rows.map { Int(qs_pixel(host.window, 50, Int32($0)) & 255) }
        #else
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 100, pixelsHigh: 80,
                                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                                     isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let graphics = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: bitmap))
        ImageRenderer(content: ShadowFixture()).render { _, draw in draw(graphics.cgContext) }
        let samples = rows.map { Int(((bitmap.colorAt(x: 50, y: $0)?.blueComponent ?? -1) * 255).rounded()) }
        #endif
        print("Serein shadow samples", samples)
        let reference = [0, 90, 143, 201, 245, 255]
        for (sample, expected) in zip(samples, reference) {
            XCTAssertEqual(Double(sample), Double(expected), accuracy: 5)
        }
    }
}
