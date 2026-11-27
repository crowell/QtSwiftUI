import SwiftUI
import XCTest

final class UnitCurveTests: XCTestCase {
    func testReactionPickerCurveAndInverse() {
        let curve = UnitCurve.bezier(startControlPoint: .init(x: 0.16, y: 1), endControlPoint: .init(x: 0.3, y: 1))
        for (time, value, velocity) in [(0.0, 0.0, 6.25), (0.125, 0.5771799087524414, 3.026911735534668),
                                        (0.25, 0.8256235122680664, 1.2225265502929688),
                                        (0.5, 0.9717788696289062, 0.2245626449584961), (1.0, 1.0, 0.0)] {
            XCTAssertEqual(curve.value(at: time), value, accuracy: 1e-6)
            XCTAssertEqual(curve.velocity(at: time), velocity, accuracy: 1e-6)
        }
        XCTAssertEqual(curve.inverse.value(at: 0.5), 0.1015625, accuracy: 1e-6)
        XCTAssertEqual(curve.inverse.velocity(at: 1), .infinity)
        XCTAssertEqual(curve.inverse.inverse, curve)
        XCTAssertEqual(curve.inverse.value(at: curve.value(at: 0.25)), 0.25, accuracy: 1e-5)
        XCTAssertEqual(Animation.timingCurve(curve, duration: 0.4), .timingCurve(0.16, 1, 0.3, 1, duration: 0.4))
    }

    func testCircularAndLinearCurves() {
        let curve = UnitCurve.circularEaseIn
        XCTAssertEqual(curve.inverse, .circularEaseOut)
        XCTAssertEqual(curve.value(at: 0.25), 0.031754163448145745, accuracy: 1e-12)
        XCTAssertEqual(curve.inverse.velocity(at: 0.25), 1.1338934190276817, accuracy: 1e-12)
        XCTAssertEqual(curve.velocity(at: 1), .infinity)
        XCTAssertEqual(UnitCurve.circularEaseOut.velocity(at: 1e-20), 7_071_067_811.865476, accuracy: 1e-5)
        XCTAssertEqual(UnitCurve.circularEaseInOut.value(at: 0.5.nextUp), 0.5000000149011612, accuracy: 1e-14)
        XCTAssertEqual(UnitCurve.circularEaseInOut.velocity(at: 0.5.nextUp), 33_554_431.999999993, accuracy: 1e-6)
        XCTAssertEqual(UnitCurve.circularEaseInOut.inverse, .circularEaseInOut)
        XCTAssertEqual(UnitCurve.circularEaseInOut.value(at: 0.75), 0.9330127018922193, accuracy: 1e-12)
        XCTAssertEqual(UnitCurve.circularEaseInOut.velocity(at: 0.5), .infinity)
        XCTAssertEqual(UnitCurve.linear.value(at: -0.125), -0.125)
        XCTAssertEqual(UnitCurve.linear.velocity(at: 0), 1)
        let diagonal = UnitCurve.bezier(startControlPoint: .zero, endControlPoint: .bottomTrailing)
        XCTAssertNotEqual(UnitCurve.linear, diagonal)
        XCTAssertEqual(diagonal.value(at: -0.125), 0)
        XCTAssertEqual(Animation.timingCurve(diagonal, duration: 1), .linear(duration: 1))
        XCTAssertEqual(Animation.timingCurve(.linear, duration: 1), .linear(duration: 1))
    }

    func testBezierBoundsAndVanishingDerivatives() {
        let curve = UnitCurve.bezier(startControlPoint: .init(x: -0.5, y: -0.7), endControlPoint: .init(x: 1.2, y: 1.3))
        XCTAssertEqual(curve.value(at: 0.125), -0.12241077423095703, accuracy: 1e-6)
        XCTAssertEqual(curve.velocity(at: 0), -.infinity)
        XCTAssertEqual(curve.value(at: 2), 1)
        XCTAssertEqual(UnitCurve.easeOut.velocity(at: 0), 1)
        let vertical = UnitCurve.bezier(startControlPoint: .init(x: 1, y: 0), endControlPoint: .init(x: 0, y: 1))
        XCTAssertEqual(vertical.velocity(at: 0.5), .infinity)
        XCTAssertEqual(vertical.inverse.velocity(at: 0.5), 0)
        XCTAssertEqual(UnitCurve.easeInOut, .bezier(startControlPoint: .init(x: 0.42, y: 0),
                                                    endControlPoint: .init(x: 0.58, y: 1)))
    }
}
