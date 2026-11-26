import XCTest
import QtBridge
@testable import SwiftUI

final class CanvasTests: XCTestCase {
    func testTransformsHolesAndGradientArePaintedIntoQtWindow() async {
        await MainActor.run {
            let host = Host(title: "Canvas") { context in
                Canvas { graphics, size in
                    graphics.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))
                    var ring = Path(CGRect(x: 0, y: 0, width: 12, height: 12))
                    ring.addRect(CGRect(x: 3, y: 3, width: 6, height: 6))
                    var copy = graphics
                    copy.translateBy(x: 4, y: 4)
                    copy.fill(ring.applying(CGAffineTransform(scaleX: 2, y: 2)), with: .color(.black), style: .init(eoFill: true))
                    let rect = CGRect(x: 40, y: 4, width: 32, height: 24)
                    graphics.fill(Path(rect), with: .linearGradient(Gradient(colors: [.black, .white]),
                                  startPoint: CGPoint(x: rect.minX, y: 0), endPoint: CGPoint(x: rect.maxX, y: 0)))
                }.resolve(context)
            }
            defer { host.close() }
            host.open(width: 80, height: 40)
            XCTAssertEqual(qs_pixel(host.window, 6, 6), 0xff000000)
            XCTAssertEqual(qs_pixel(host.window, 14, 14), 0xffffffff)
            XCTAssertEqual(qs_pixel(host.window, 25, 25), 0xff000000)
            XCTAssertEqual(qs_pixel(host.window, 31, 31), 0xffffffff)
            XCTAssertLessThan(qs_pixel(host.window, 42, 16) & 255, 32)
            XCTAssertGreaterThan(qs_pixel(host.window, 68, 16) & 255, 215)
        }
    }
    func testPathBoundsAndHitTesting() {
        var p = Path()
        XCTAssertTrue(p.boundingRect.isNull)
        XCTAssertNil(p.currentPoint)
        p.addRects([CGRect(x: 2, y: 3, width: 20, height: 30), CGRect(x: 8, y: 9, width: 4, height: 5)])
        let moved = p.offsetBy(dx: 2, dy: -1)
        XCTAssertEqual(moved.boundingRect, CGRect(x: 4, y: 2, width: 20, height: 30))
        XCTAssertTrue(moved.contains(CGPoint(x: 11, y: 10)))
        XCTAssertFalse(moved.contains(CGPoint(x: 11, y: 10), eoFill: true))
    }
    func testAffineCompositionAndInverse() {
        let t = CGAffineTransform(translationX: 8, y: -4).scaledBy(x: 3, y: 2)
        let point = CGPoint(x: 2, y: 3)
        XCTAssertEqual(point.applying(t), CGPoint(x: 14, y: 2))
        let roundTrip = point.applying(t).applying(t.inverted())
        XCTAssertEqual(roundTrip.x, point.x, accuracy: 1e-12)
        XCTAssertEqual(roundTrip.y, point.y, accuracy: 1e-12)
        XCTAssertEqual(CGRect(x: 1, y: 2, width: 3, height: 4).applying(t), CGRect(x: 11, y: 0, width: 9, height: 8))
    }
}
