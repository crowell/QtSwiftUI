import SwiftUI
import XCTest
#if os(Linux)
import QtBridge
#endif

@Observable private final class PressLog {
    var enabled = true
    var resets: [Bool] = []
    var ended = 0
}

private struct PressTarget: View {
    let log: PressLog
    @GestureState private var pressing: Bool
    init(log: PressLog) {
        self.log = log
        _pressing = GestureState(wrappedValue: false, reset: { previous, transaction in
            log.resets.append(previous)
            transaction.animation = nil
        })
    }
    var body: some View {
        ZStack {
            (pressing ? Color.white : Color.black)
            if log.enabled {
                Color.clear.contentShape(Rectangle()).gesture(DragGesture(minimumDistance: 0)
                    .updating($pressing) { _, state, _ in state = true }
                    .onEnded { _ in log.ended += 1 })
            }
        }
    }
}

final class GestureStateTests: XCTestCase {
    @MainActor func testUpdatingAndResetOnReleaseAndRemoval() async throws {
        let log = PressLog()
        let window = try await ScreenWindow(PressTarget(log: log), width: 100, height: 60)
        defer { window.close() }
        XCTAssertEqual(window.pixel(70, 30), 0)
        try await window.pointer(20, 30, down: true)
        XCTAssertEqual(window.pixel(70, 30), 0xffffff)
        try await window.pointer(20, 30, down: false)
        XCTAssertEqual(window.pixel(70, 30), 0)
        XCTAssertEqual(log.ended, 1)
        XCTAssertEqual(log.resets, [true])
        try await window.pointer(20, 30, down: true)
        XCTAssertEqual(window.pixel(70, 30), 0xffffff)
        log.enabled = false
        try await Task.sleep(for: .milliseconds(70))
        #if os(Linux)
        qs_flush()
        qs_flush()
        #endif
        XCTAssertEqual(window.pixel(70, 30), 0)
        XCTAssertEqual(log.resets, [true, true])
        XCTAssertEqual(log.ended, 1)
    }
}
