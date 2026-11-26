import SwiftUI
import XCTest
#if os(Linux)
import QtBridge
@testable import SwiftUI
#else
import AppKit

private final class MagnifyEvent: NSEvent {
    var delta: CGFloat = 0
    var phaseValue: NSEvent.Phase = []
    var target: NSWindow!
    var location = CGPoint.zero
    var sampleTime = 0.0
    override var type: EventType { .magnify }
    override var magnification: CGFloat { delta }
    override var phase: Phase { phaseValue }
    override var windowNumber: Int { target.windowNumber }
    override var window: NSWindow? { target }
    override var locationInWindow: NSPoint { location }
    override var timestamp: TimeInterval { sampleTime }
    override var modifierFlags: ModifierFlags { [] }
}
#endif

extension ScreenWindow {
    /// Feed the same physical scale sequence to each toolkit. AppKit accepts additive deltas
    /// and Qt accepts multiplicative deltas relative to the preceding scale.
    func pinch(at point: CGPoint, factors: [CGFloat]) async throws {
        var previous = CGFloat(1)
        let samples = [CGFloat(1)] + factors + [factors.last ?? 1]
        for (index, factor) in samples.enumerated() {
            let began = index == 0, ended = index == samples.count - 1
            let millis = 1_000_000 + 100 * index
            #if os(Linux)
            qs_native_pinch(host.window, began ? 0 : ended ? 2 : 1, point.x, point.y, factor / previous - 1, UInt(millis))
            #else
            let event = MagnifyEvent()
            event.target = window
            event.phaseValue = began ? .began : ended ? .ended : .changed
            event.delta = factor - previous
            event.location = CGPoint(x: point.x, y: CGFloat(height) - point.y)
            event.sampleTime = Double(millis) / 1000
            window.sendEvent(event)
            #endif
            previous = factor
            try await settle()
        }
    }
}

final class MagnifyTests: XCTestCase {
    @MainActor func testThresholdScaleAnchorAndCompletion() async throws {
        XCTAssertEqual(MagnifyGesture().minimumScaleDelta, 0.01)
        var changed: [MagnifyGesture.Value] = [], ended: [MagnifyGesture.Value] = []
        let view = Color.blue.frame(width: 80, height: 60)
            .gesture(MagnifyGesture().onChanged { changed.append($0) }.onEnded { ended.append($0) })
        let window = try await ScreenWindow(view, width: 120, height: 90)
        defer { window.close() }
        let point = CGPoint(x: 45, y: 57)
        try await window.pinch(at: point, factors: [1.004, 1.03, 1.23])
        XCTAssertEqual(changed.count, 2)
        let first = try XCTUnwrap(changed.first)
        XCTAssertEqual(first.magnification, 1.03, accuracy: 0.00001)
        XCTAssertEqual(first.time.timeIntervalSinceReferenceDate, 1000.2, accuracy: 0.00001)
        XCTAssertEqual(first.velocity, 0.26, accuracy: 0.00001)
        XCTAssertEqual(first.startLocation, CGPoint(x: 25, y: 42))
        XCTAssertEqual(first.startAnchor, UnitPoint(x: 0.3125, y: 0.7))
        XCTAssertEqual(ended.count, 1)
        XCTAssertEqual(try XCTUnwrap(ended.first).magnification, 1.23, accuracy: 0.00001)
        try await window.pinch(at: point, factors: [0.8])
        XCTAssertEqual(ended.count, 2)
        XCTAssertEqual(try XCTUnwrap(ended.last).magnification, 0.8, accuracy: 0.00001)
    }

    @MainActor func testLegacyGestureAndIndirectInputMask() async throws {
        var scaled: [CGFloat] = []
        let view = Color.red.frame(width: 60, height: 40)
            .gesture(MagnificationGesture(minimumScaleDelta: 0.1).onEnded { scaled.append($0) })
        let window = try await ScreenWindow(view, width: 60, height: 40)
        defer { window.close() }
        try await window.pinch(at: .init(x: 30, y: 20), factors: [1.04])
        XCTAssertTrue(scaled.isEmpty)
        try await window.pinch(at: .init(x: 30, y: 20), factors: [0.75])
        XCTAssertEqual(scaled, [0.75])
        #if os(Linux)
        for mask: GestureInputKinds in [.directTouch, .indirectTouch, []] {
            var endings = 0
            let view = Color.blue.gesture(MagnifyGesture(inputKinds: mask).onEnded { _ in endings += 1 })
            let filtered = try await ScreenWindow(view, width: 60, height: 40)
            try await filtered.pinch(at: .init(x: 30, y: 20), factors: [1.5])
            XCTAssertEqual(endings, mask == .indirectTouch ? 1 : 0)
            filtered.close()
        }
        #endif
    }
}
