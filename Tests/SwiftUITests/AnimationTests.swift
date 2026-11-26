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
