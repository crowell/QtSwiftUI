import XCTest
import SwiftUI
@testable import CallDiagnostics
#if os(Linux)
import QtBridge
@testable import SwiftUI
#endif

final class AudioIndicatorTests: XCTestCase {
    func testVectorInterpolationAndTangentArc() {
        let a = AnimatablePair(2.0, Float(4)), b = AnimatablePair(6.0, Float(12))
        let mid = a.interpolated(towards: b, amount: 0.25)
        XCTAssertEqual(mid.first, 3)
        XCTAssertEqual(mid.second, 6)
        XCTAssertEqual(mid.magnitudeSquared, 45)
        var arc = Path()
        arc.move(to: .zero)
        arc.addArc(tangent1End: CGPoint(x: 10, y: 0), tangent2End: CGPoint(x: 10, y: 10), radius: 5)
        XCTAssertEqual(arc.currentPoint?.x ?? -1, 10, accuracy: 0.0001)
        XCTAssertEqual(arc.currentPoint?.y ?? -1, 5, accuracy: 0.0001)
    }

    @MainActor func testProductionAudioBarsPath() {
        var bars = AudioBars(level: 0)
        bars.animatableData = 0.5
        let bounds = bars.path(in: CGRect(x: 0, y: 0, width: 28, height: 28)).boundingRect
        XCTAssertEqual(bounds.minX, 2, accuracy: 0.001)
        XCTAssertEqual(bounds.width, 24, accuracy: 0.001)
        XCTAssertEqual(bounds.height, 13, accuracy: 0.001)
    }

    #if os(Linux)
    @MainActor func testLiveProductionIndicatorInterpolatesLevel() async {
        var level = 0.0
        var now = 2.0
        let host = Host(title: "Audio", animationClock: { now }) {
            CallingAudioIndicator(hasAudio: true, audioLevel: level, shouldShowSpeaking: true)
                .frame(width: 28, height: 28).background(Color.black).resolve($0)
        }
        defer { host.close() }
        host.open(width: 28, height: 28)
        func intensity(_ y: Int32) -> UInt32 {
            host.update()
            qs_flush()
            return qs_pixel(host.window, 14, y) & 255
        }
        level = 1
        XCTAssertLessThan(intensity(11), 100)
        now += 0.1
        XCTAssertGreaterThan(intensity(11), 180)
        XCTAssertLessThan(intensity(9), 100)
        now += 0.11
        XCTAssertGreaterThan(intensity(9), 180)
    }
    #endif
}
