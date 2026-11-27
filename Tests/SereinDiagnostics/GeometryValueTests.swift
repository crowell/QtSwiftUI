import Foundation
import SwiftUI
import XCTest

final class GeometryValueTests: XCTestCase {
    func testCornerInsetsByEdge() {
        let corners = RectangleCornerInsets(topLeading: CGSize(width: 5, height: 3), topTrailing: CGSize(width: 13, height: 9),
                                            bottomLeading: CGSize(width: 7, height: 19), bottomTrailing: CGSize(width: 23, height: 29))
        let initial = EdgeInsets(top: 2, leading: 11, bottom: 37, trailing: -4)
        for raw: Int8 in 0..<16 {
            let edges = Edge.Set(rawValue: raw)
            let expected = EdgeInsets(top: edges.contains(.top) ? 11 : 2, leading: edges.contains(.leading) ? 18 : 11,
                                      bottom: edges.contains(.bottom) ? 66 : 37, trailing: edges.contains(.trailing) ? 19 : -4)
            XCTAssertEqual(initial.inset(by: corners, edges: edges), expected)
        }
        let negative = CGSize(width: -6, height: -4)
        let inward = RectangleCornerInsets(topLeading: negative, topTrailing: negative, bottomLeading: negative, bottomTrailing: negative)
        XCTAssertEqual(EdgeInsets().inset(by: inward), EdgeInsets(top: -4, leading: -6, bottom: -4, trailing: -6))
        XCTAssertEqual(initial.inset(by: .init()), initial)
        XCTAssertEqual(Set([corners, corners, inward]).count, 2)
    }

    func testInsetAndAngleArithmetic() {
        let a = EdgeInsets(top: 1, leading: -2, bottom: 3, trailing: -4)
        XCTAssertEqual(a.animatableData, .init(1, .init(-2, .init(3, -4))))
        XCTAssertEqual(a.magnitude, sqrt(30), accuracy: 1e-12)
        var b = EdgeInsets()
        b.animatableData = .init(5, .init(4, .init(3, 2)))
        XCTAssertEqual(a + b, EdgeInsets(top: 6, leading: 2, bottom: 6, trailing: -2))
        XCTAssertEqual(a - b, EdgeInsets(top: -4, leading: -6, bottom: 0, trailing: -6))
        var result = b
        result += a
        result -= b
        result *= 2
        result /= -4
        XCTAssertEqual(result, -a / 2)
        result.negate()
        XCTAssertEqual(result, a * 0.5)

        var angle = Angle.radians(-3.5)
        XCTAssertEqual(angle.animatableData, -448)
        XCTAssertEqual(angle.magnitude, 448)
        angle.negate()
        angle += .radians(1)
        XCTAssertEqual(angle * 2 - .radians(2), .radians(7))
        XCTAssertEqual(-angle / 2, .radians(-2.25))
        XCTAssertEqual(Angle(), .zero)
        XCTAssertTrue(Angle(degrees: Double.greatestFiniteMagnitude).radians.isFinite)
    }

    func testUnitPointAndAngleCoding() throws {
        let decoder = JSONDecoder(), encoder = JSONEncoder()
        let point = UnitPoint(x: -2, y: 3.5)
        XCTAssertEqual(UnitPoint(), .zero)
        XCTAssertEqual(String(decoding: try encoder.encode(point), as: UTF8.self), "[-2,3.5]")
        XCTAssertEqual(try decoder.decode(UnitPoint.self, from: Data("[-2,3.5,9]".utf8)), point)
        for invalid in ["[]", "[1]", "[1,null]", "{\"x\":-2,\"y\":3.5}"] {
            XCTAssertThrowsError(try decoder.decode(UnitPoint.self, from: Data(invalid.utf8)))
        }
        var moved = point
        XCTAssertEqual(moved.animatableData, .init(-256, 448))
        let position: UnitPoint.AnimatableData = .init(512, 640)
        moved.animatableData = position
        XCTAssertEqual(moved, UnitPoint(x: 4, y: 5))

        let angle = Angle.radians(-1.25)
        XCTAssertEqual(String(decoding: try encoder.encode(angle), as: UTF8.self), "-1.25")
        XCTAssertEqual(try decoder.decode(Angle.self, from: Data("-1.25".utf8)), angle)
        XCTAssertThrowsError(try decoder.decode(Angle.self, from: Data("[-1.25]".utf8)))
    }
}
