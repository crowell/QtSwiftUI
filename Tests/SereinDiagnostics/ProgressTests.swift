import SwiftUI
import XCTest
@testable import CallDiagnostics
#if os(Linux)
import QtBridge
@testable import SwiftUI
#else
import AppKit
#endif

final class ProgressTests: XCTestCase {
    @MainActor func testQuarterRingStartsAtTwelveOClock() async throws {
        let ring = AxoBaseSpinner.Root(size: 40, weight: .medium, variant: .default,
                                       value: .progress(completed: 25, total: 100), track: false)
            .frame(width: 60, height: 60).background(Color.white)
        let points = [(30, 11), (43, 16), (48, 29), (11, 30), (30, 49), (30, 30)]
        #if os(Linux)
        let host = Host(title: "Progress") { ring.resolve($0) }
        defer { host.close() }
        host.open(width: 60, height: 60)
        let values = points.map { Int(qs_pixel(host.window, Int32($0.0), Int32($0.1)) & 255) }
        #else
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 60, pixelsHigh: 60,
                                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                                     isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let graphics = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: bitmap))
        ImageRenderer(content: ring).render { _, draw in draw(graphics.cgContext) }
        let values = points.map { Int(((bitmap.colorAt(x: $0.0, y: $0.1)?.blueComponent ?? -1) * 255).rounded()) }
        #endif
        for painted in values.prefix(3) { XCTAssertLessThan(painted, 150, "Ring samples: \(values)") }
        for empty in values.suffix(3) { XCTAssertEqual(empty, 255, "Ring samples: \(values)") }
    }
}
