import SwiftUI
import XCTest

final class PathElementTests: XCTestCase {
    func testMutablePathCopyPreservesQuadraticControlsAndTrueBounds() {
        let mutable = CGMutablePath()
        mutable.addLine(to: CGPoint(x: 4, y: 8))
        XCTAssertTrue(mutable.isEmpty)
        let start = CGPoint(x: 1, y: 2), end = CGPoint(x: 4, y: 2), control = CGPoint(x: 3, y: 8)
        mutable.move(to: start)
        mutable.addQuadCurve(to: end, control: control)
        let path = Path(mutable)
        mutable.addLine(to: CGPoint(x: 20, y: 20))
        var steps: [Path.Element] = []
        path.forEach { steps.append($0) }
        XCTAssertEqual(steps, [.move(to: start), .quadCurve(to: end, control: control)])
        let copy = path.cgPath
        XCTAssertEqual(copy.boundingBox, CGRect(x: 1, y: 2, width: 3, height: 6))
        XCTAssertEqual(copy.boundingBoxOfPath, CGRect(x: 1, y: 2, width: 3, height: 3))
        XCTAssertEqual(Path(copy).currentPoint, end)
        let translated = path.applying(.init(translationX: 7, y: -1)).cgPath
        XCTAssertEqual(translated.boundingBoxOfPath, CGRect(x: 8, y: 1, width: 3, height: 3))
    }
    func testEllipseAndClosedRectangleEnumerateTheirContours() {
        let rect = CGRect(x: 1, y: 2, width: 4, height: 6)
        var rectangle: [Path.Element] = [], ellipse: [Path.Element] = []
        Path(rect).forEach { rectangle.append($0) }
        Path(ellipseIn: rect).forEach { ellipse.append($0) }
        XCTAssertEqual(rectangle.count, 5)
        XCTAssertEqual(rectangle.last, .closeSubpath)
        XCTAssertEqual(ellipse.count, 6)
        XCTAssertEqual(ellipse.first, .move(to: CGPoint(x: 5, y: 5)))
        XCTAssertEqual(ellipse.last, .closeSubpath)
    }
}
