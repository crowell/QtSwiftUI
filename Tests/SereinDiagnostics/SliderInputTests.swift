import XCTest
import SwiftUI
@testable import CallDiagnostics
#if os(Linux)
import QtBridge
@testable import SwiftUI
#else
import AppKit
#endif

@Observable private final class PlaybackPosition { var value = 50.0 }

final class SliderInputTests: XCTestCase {
    @MainActor func testKeyPhaseValuesAndProductionTrack() async throws {
        XCTAssertEqual([KeyPress.Phases.down, .repeat, .up, .all].map(\.rawValue), [1, 2, 4, Int.max])
        XCTAssertEqual(KeyPress.Phases([.down, .up]).debugDescription, "[.down, .up]")
        let position = PlaybackPosition()
        let binding = Binding(get: { position.value }, set: { position.value = $0 })
        let view = CallDiagnostics.Slider(label: "Position", value: binding)
            .frame(width: 160, height: 40).background(Color.white)
        #if os(Linux)
        let host = Host(title: "Position") { view.resolve($0) }
        host.open(width: 160, height: 40)
        defer { host.close() }
        func red(_ x: Int) -> Int { Int((qs_pixel(host.window, Int32(x), 20) >> 16) & 255) }
        #else
        let image = NSBitmapImageRep(cgImage: try XCTUnwrap(ImageRenderer(content: view).cgImage))
        func red(_ x: Int) -> Int { Int(image.colorAt(x: x, y: 20)!.redComponent * 255) }
        #endif
        XCTAssertLessThan(red(84), 100, "Thumb at 50 percent")
        XCTAssertGreaterThan(red(30), 180, "Unoccupied track")
        #if os(Linux)
        XCTAssertEqual(qs_drag_pointer(host.window, 30, 20, 140, 20, 5), 1)
        XCTAssertEqual(position.value, 87.5)
        XCTAssertEqual(qs_accessible_element(host.window, "Position", 0, "Increase"), 1)
        XCTAssertEqual(position.value, 88.5)
        XCTAssertEqual(qs_accessible_element(host.window, "Position", 0, "Decrease"), 1)
        XCTAssertEqual(position.value, 87.5)
        _ = qs_send_key_sequence(host.window, "Home")
        XCTAssertEqual(position.value, 0)
        _ = qs_send_key_sequence(host.window, "Right")
        XCTAssertEqual(position.value, 1)
        _ = qs_send_key_sequence(host.window, "End")
        XCTAssertEqual(position.value, 100)
        _ = qs_send_key_sequence(host.window, "Left")
        XCTAssertEqual(position.value, 99)
        for _ in 0..<20 {
            if qs_accessible_value_is(host.window, "Position", "99") != 0 { break }
            try await Task.sleep(for: .milliseconds(10))
            qs_flush()
        }
        XCTAssertEqual(qs_accessible_value_is(host.window, "Position", "99"), 1)
        XCTAssertLessThan(red(159), 100)
        #endif
    }
}
