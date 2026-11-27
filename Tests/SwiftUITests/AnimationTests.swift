import XCTest
import QtBridge
@testable import SwiftUI

final class AnimationTests: XCTestCase {
    func testDelayedMovementWaitsThenRunsForItsFullDuration() {
        let base = Animation.linear(duration: 1)
        let delayed = base.delay(0.25).delay(0.5)
        XCTAssertNotEqual(base, base.delay(0))
        XCTAssertNotEqual(delayed, base.delay(0.75))
        let value = AnimatedValue(0.0)
        value.update(to: 1, at: 10, animation: delayed)
        XCTAssertEqual(value.sample(at: 10.7), 0)
        XCTAssertTrue(value.isAnimating)
        XCTAssertEqual(value.sample(at: 11.25), 0.5, accuracy: 0.001)
        XCTAssertEqual(value.sample(at: 11.75), 1)
        XCTAssertFalse(value.isAnimating)
    }

    func testUnitCurveDrivesThePresentationValue() {
        let opacity = AnimatedValue(0.0)
        opacity.update(to: 1, at: 10, animation: .timingCurve(.circularEaseInOut, duration: 2))
        XCTAssertEqual(opacity.sample(at: 10.5), 0.0669872981077807, accuracy: 1e-12)
        XCTAssertEqual(opacity.sample(at: 11), 0.5, accuracy: 1e-12)
        XCTAssertEqual(opacity.sample(at: 11.5), 0.9330127018922193, accuracy: 1e-12)
        XCTAssertEqual(opacity.sample(at: 12), 1)
        XCTAssertFalse(opacity.isAnimating)
    }

    func testPersistentSpringRetargetCarriesVelocityAndBlendsResponse() {
        let initial = Animation.spring(response: 0.75, dampingFraction: 0.55)
        let switching = 0.12, step = 0.000001
        func retarget(blend: Double) -> AnimatedValue<Double> {
            let value = AnimatedValue(0.0)
            value.update(to: 1, at: 0, animation: initial)
            value.update(to: -1, at: switching, animation: .spring(response: 0.2, dampingFraction: 0.7, blendDuration: blend))
            return value
        }
        let reference = initial.fraction(at: switching)
        let oldVelocity = (reference - initial.fraction(at: switching - step)) / step
        let blended = retarget(blend: 0.25)
        let immediate = retarget(blend: 0)
        for value in [blended, immediate] {
            XCTAssertEqual(value.sample(at: switching), reference, accuracy: 1e-10)
            XCTAssertEqual((value.sample(at: switching + step) - reference) / step, oldVelocity, accuracy: 0.002)
        }
        XCTAssertGreaterThan(blended.sample(at: switching + 0.05), immediate.sample(at: switching + 0.05) + 0.3)
        XCTAssertEqual(blended.sample(at: 3), -1)
        XCTAssertFalse(blended.isAnimating)
    }

    @MainActor func testInterruptedOpacityAnimationStartsAtDisplayedValue() async {
        var target = 0.0
        var time = 100.0
        let host = Host(title: "Animation", animationClock: { time }) { ctx in
            ZStack {
                Color.white
                Rectangle().fill(.black).opacity(target).animation(.linear(duration: 1), value: target)
            }.resolve(ctx)
        }
        defer { host.close() }
        host.open(width: 32, height: 32)
        func blue() -> Double {
            host.update()
            qs_flush()
            return Double(qs_pixel(host.window, 16, 16) & 255)
        }
        XCTAssertEqual(blue(), 255)
        target = 1
        XCTAssertEqual(blue(), 255)
        time += 0.5
        XCTAssertEqual(blue(), 128, accuracy: 1)
        target = 0
        XCTAssertEqual(blue(), 128, accuracy: 1)
        time += 0.5
        XCTAssertEqual(blue(), 192, accuracy: 1)
        time += 0.5
        XCTAssertEqual(blue(), 255)
    }
}
