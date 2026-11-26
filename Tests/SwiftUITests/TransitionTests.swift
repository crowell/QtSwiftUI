import XCTest
import QtBridge
@testable import SwiftUI

final class TransitionTests: XCTestCase {
    @MainActor func testOpacityAcrossInsertionRemovalAndReinsertion() async {
        var time = 10.0, shown = false
        let host = Host(title: "Transition test", animationClock: { time }) { context in
            ZStack {
                Color.white
                if shown { Color.black.frame(width: 24, height: 24).transition(.opacity) }
            }.animation(.linear(duration: 1), value: shown).resolve(context)
        }
        defer { host.close() }
        host.open(width: 32, height: 32)
        func sample() -> Double {
            host.update()
            qs_flush()
            return Double(qs_pixel(host.window, 16, 16) & 255)
        }
        XCTAssertEqual(sample(), 255)
        shown = true
        XCTAssertEqual(sample(), 255)
        time += 0.5
        XCTAssertEqual(sample(), 128, accuracy: 2)
        time += 0.5
        XCTAssertEqual(sample(), 0)
        shown = false
        XCTAssertEqual(sample(), 0)
        time += 0.5
        XCTAssertEqual(sample(), 128, accuracy: 2)
        shown = true
        XCTAssertEqual(sample(), 128, accuracy: 2)
        time += 1
        XCTAssertEqual(sample(), 0)
        shown = false
        _ = sample()
        time += 1
        XCTAssertEqual(sample(), 255)
    }
}
