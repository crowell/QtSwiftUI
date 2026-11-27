import SwiftUI
import XCTest

final class SpringTests: XCTestCase {
    func testMotionForceAndSettlingAcrossDampingRegimes() {
        let cases: [(Double, Bool, Double, Double, Double, Double, Double)] = [
            (8, false, 2.507693578225427, 17.937605856930837, 276, 4.003183783825123, 50),
            (20, false, 1.8061743706455573, 11.03638323514327, 240, 1.9, 50),
            (40, false, 1.8061743706455573, 11.03638323514327, 240, 1.9, 50),
            (40, true, 1.1947649347453093, 12.317154616390456, 1980, 5.3, 350),
        ]
        for (damping, allowOver, displacement, speed, force, settling, stiffness) in cases {
            let spring = Spring(mass: 2, stiffness: 50, damping: damping, allowOverDamping: allowOver)
            XCTAssertEqual(spring.mass, 2)
            XCTAssertEqual(spring.stiffness, stiffness, accuracy: 1e-10)
            XCTAssertEqual(spring.value(target: 6.0, initialVelocity: 3, time: 0.2), displacement, accuracy: 1e-10)
            XCTAssertEqual(spring.velocity(target: 6.0, initialVelocity: 3, time: 0.2), speed, accuracy: 1e-10)
            var x = 1.0, v = 3.0
            spring.update(value: &x, velocity: &v, target: 7, deltaTime: 0)
            XCTAssertEqual(x, 1)
            XCTAssertEqual(v, 3)
            spring.update(value: &x, velocity: &v, target: 7, deltaTime: 0.2)
            XCTAssertEqual(x, displacement + 1, accuracy: 1e-10)
            XCTAssertEqual(v, speed, accuracy: 1e-10)
            XCTAssertEqual(spring.force(target: 7.0, position: 1, velocity: 3), force, accuracy: 1e-10)
            XCTAssertEqual(spring.settlingDuration, settling, accuracy: 1e-10)
        }
    }

    func testPresetsParametersAndAnimationFactories() {
        for (spring, bounce) in [(Spring.smooth, 0.0), (.snappy, 0.15), (.bouncy, 0.3)] {
            XCTAssertEqual(spring.duration, 0.5, accuracy: 1e-12)
            XCTAssertEqual(spring.bounce, bounce, accuracy: 1e-12)
        }
        let spring = Spring.bouncy(duration: 0.8, extraBounce: 0.1)
        XCTAssertEqual(spring.response, 0.8, accuracy: 1e-12)
        XCTAssertEqual(spring.dampingRatio, 0.6, accuracy: 1e-12)
        XCTAssertEqual(Spring(duration: 0.63, bounce: -0.4).dampingRatio, 5.0 / 3, accuracy: 1e-12)
        let physical = Spring(mass: 2, stiffness: 50, damping: 8)
        XCTAssertNotEqual(physical, Spring(mass: 1, stiffness: 25, damping: 4))
        XCTAssertEqual(Animation.spring(physical, blendDuration: 0.2),
                       .spring(duration: physical.duration, bounce: physical.bounce, blendDuration: 0.2))
        XCTAssertEqual(Animation.interpolatingSpring(physical, initialVelocity: 2),
                       .interpolatingSpring(duration: physical.duration, bounce: physical.bounce, initialVelocity: 2))
    }

    func testSettlingThresholdsAndLongResponses() {
        let spring = Spring(settlingDuration: 1, dampingRatio: 0.4)
        XCTAssertEqual(spring.damping, 12.157282480632565, accuracy: 1e-9)
        XCTAssertEqual(Spring(settlingDuration: 0.1, dampingRatio: 0.4, epsilon: 0.1).stiffness,
                       1356.9480863617466, accuracy: 1e-8)
        XCTAssertEqual(Spring(settlingDuration: 1, dampingRatio: 2), Spring(settlingDuration: 1, dampingRatio: 1))
        XCTAssertEqual(Spring(response: 70, dampingRatio: 1).settlingDuration, 0)
        XCTAssertEqual(Spring(response: 15, dampingRatio: 3).settlingDuration(
            target: AnimatablePair(1.0, 0.0), initialVelocity: AnimatablePair(0.0, 1.0), epsilon: 0.001),
                       97.7, accuracy: 1e-8)
        XCTAssertEqual(Spring(mass: 2, stiffness: 50, damping: 0).settlingDuration, .infinity)
    }

    @MainActor func testAnimatableOverloadsPreserveTargetMetadata() {
        struct Marker: Animatable {
            var label: String
            var animatableData: AnimatablePair<Double, Double>
        }
        let spring = Spring(mass: 2, stiffness: 50, damping: 8)
        let start = Marker(label: "start", animatableData: .init(10, -4))
        let end = Marker(label: "end", animatableData: .init(17, 2))
        let v = Marker(label: "velocity", animatableData: .init(3, 5))
        let position = Marker(label: "position", animatableData: .init(11, 3))
        let samples: [(Marker, Double, Double)] = [
            (spring.value(fromValue: start, toValue: end, initialVelocity: v, time: 0.2),
             12.867608627477896, -1.260170899967497),
            (spring.velocity(fromValue: start, toValue: end, initialVelocity: v, time: 0.2),
             20.83929987951929, 18.289233671197596),
            (spring.force(fromValue: start, toValue: end, position: position, velocity: v), -224, 110),
        ]
        for (sample, x, y) in samples {
            XCTAssertEqual(sample.label, end.label)
            XCTAssertEqual(sample.animatableData.first, x, accuracy: 1e-10)
            XCTAssertEqual(sample.animatableData.second, y, accuracy: 1e-10)
        }
        XCTAssertEqual(spring.settlingDuration(fromValue: start, toValue: end, initialVelocity: v, epsilon: 0.001),
                       spring.settlingDuration(target: end.animatableData - start.animatableData,
                                               initialVelocity: v.animatableData, epsilon: 0.001))
    }
}
