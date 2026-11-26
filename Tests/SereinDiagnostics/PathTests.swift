import SwiftUI
import XCTest

final class PathTests: XCTestCase {
    func testTrimUsesArcLengthAcrossSubpaths() throws {
        var path = Path()
        path.addLines([CGPoint(x: 0, y: 0), CGPoint(x: 20, y: 0), CGPoint(x: 20, y: 60)])
        let middle = path.trimmedPath(from: 0.25, to: 0.75)
        XCTAssertEqual(middle.boundingRect, CGRect(x: 20, y: 0, width: 0, height: 40))
        XCTAssertEqual(middle.currentPoint, CGPoint(x: 20, y: 40))
        XCTAssertTrue(path.trimmedPath(from: 0.75, to: 0.25).isEmpty)
        let outside = path.trimmedPath(from: 1.5, to: 2)
        XCTAssertTrue(outside.boundingRect.isNull)
        XCTAssertNil(outside.currentPoint)

        var disjoint = Path()
        disjoint.addLines([CGPoint(x: 0, y: 0), CGPoint(x: 10, y: 0)])
        disjoint.addLines([CGPoint(x: 50, y: 0), CGPoint(x: 60, y: 0)])
        let stroked = disjoint.trimmedPath(from: 0.25, to: 0.75).strokedPath(.init(lineWidth: 2))
        XCTAssertTrue(stroked.contains(CGPoint(x: 8, y: 0)))
        XCTAssertTrue(stroked.contains(CGPoint(x: 52, y: 0)))
        XCTAssertFalse(stroked.contains(CGPoint(x: 30, y: 0)))
    }

    func testTrimKeepsCubicCurvature() throws {
        var arch = Path()
        arch.move(to: .zero)
        arch.addCurve(to: CGPoint(x: 40, y: 0), control1: CGPoint(x: 0, y: 40), control2: CGPoint(x: 40, y: 40))
        let half = arch.trimmedPath(from: 0, to: 0.5)
        let end = try XCTUnwrap(half.currentPoint)
        XCTAssertEqual(end.x, 20, accuracy: 0.12)
        XCTAssertEqual(end.y, 30, accuracy: 0.12)
        XCTAssertTrue(half.strokedPath(.init(lineWidth: 3)).contains(CGPoint(x: 6.25, y: 22.5)))
    }
}
