import XCTest
import SwiftUI
#if !os(Linux)
import AppKit
#endif

private nonisolated func tapValue(_ enabled: Bool) -> AnyGesture<Int?> {
    let tap: TapGesture? = enabled ? TapGesture() : nil
    return AnyGesture(AnyGesture(tap).map { nil as Int? })
}

private nonisolated func attach<V: View, G: Gesture>(_ gesture: G, to view: V, enabled: Bool) -> some View {
    view.gesture(gesture, isEnabled: enabled)
}

private struct ChangingDragLabel: View {
    @State private var count = 0
    var observe: (Int?) -> Void

    var body: some View {
        Text("Changes \(count)").frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(AnyGesture(DragGesture(minimumDistance: 0).map { _ in nil as Int? })
                .onChanged { value in
                    count += 1
                    observe(value)
                })
    }
}

final class MappedGestureTests: XCTestCase {
    @MainActor func testNilChangesStayDistinctWhileGestureRebuilds() async throws {
        var received: [Int?] = []
        let window = try await ScreenWindow(ChangingDragLabel { received.append($0) }, width: 100, height: 60)
        defer { window.close() }
        for _ in 0..<2 {
            try await window.drag(from: CGPoint(x: 15, y: 30), to: CGPoint(x: 80, y: 30))
        }
        XCTAssertEqual(received, [nil, nil])
    }

    @MainActor func testDoubleClickRecognizesSimultaneouslyWithSelectableText() async throws {
        let plain = Text("Select this message")
        var rich = AttributedString("Select this message")
        rich.foregroundColor = .blue
        for label in [plain, Text(rich)] {
            var replies = 0
            let view = label.textSelection(.enabled)
                .simultaneousGesture(TapGesture(count: 2).onEnded { replies += 1 })
            let window = try await ScreenWindow(view, width: 160, height: 60)
            defer { window.close() }
            #if os(Linux)
            try await window.click(78, 30)
            try await window.click(78, 30)
            #else
            for count in 1...2 {
                for type: NSEvent.EventType in [.leftMouseDown, .leftMouseUp] {
                    window.tick += 1
                    let event = try XCTUnwrap(NSEvent.mouseEvent(with: type, location: CGPoint(x: 78, y: 30),
                        modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime + Double(window.tick) * 0.016,
                        windowNumber: window.window.windowNumber, context: nil, eventNumber: window.tick,
                        clickCount: count, pressure: type == .leftMouseUp ? 0 : 1))
                    window.window.sendEvent(event)
                }
            }
            try await window.settle()
            #endif
            XCTAssertEqual(replies, 1)
        }
    }

    @MainActor func testOptionalTapPreservesNilOutputAndDisabledInput() async throws {
        for (present, enabled) in [(true, true), (false, true), (true, false)] {
            var received: [Int?] = []
            let gesture = tapValue(present).onEnded { received.append($0) }
            let window = try await ScreenWindow(attach(gesture, to: Color.blue, enabled: enabled), width: 100, height: 60)
            defer { window.close() }
            try await window.click(30, 30)
            XCTAssertEqual(received, present && enabled ? [nil] : [])
        }
    }

    @MainActor func testMappedDragDeliversDistinctChangesAndResetsForNextDrag() async throws {
        var changed: [Bool] = [], ended: [Bool] = []
        let gesture = DragGesture(minimumDistance: 0)
            .map { $0.location.x >= 50 }
            .onChanged { changed.append($0) }
            .onEnded { ended.append($0) }
        let window = try await ScreenWindow(Color.blue.gesture(AnyGesture(gesture)), width: 120, height: 80)
        defer { window.close() }
        for _ in 0..<2 {
            try await window.drag(from: CGPoint(x: 15, y: 40), to: CGPoint(x: 90, y: 40))
        }
        XCTAssertEqual(changed, [false, true, false, true])
        XCTAssertEqual(ended, [true, true])
    }

    @MainActor func testDragCrossingThresholdOnlyOnRelease() async throws {
        var changed: [CGFloat] = [], ended: [CGFloat] = []
        let drag = DragGesture(minimumDistance: 10).map { $0.location.x }
            .onChanged { changed.append($0) }.onEnded { ended.append($0) }
        let window = try await ScreenWindow(Color.blue.gesture(drag), width: 120, height: 80)
        defer { window.close() }
        try await window.pointer(25, 40, down: true)
        try await window.pointer(28, 40, down: false)
        try await window.pointer(25, 40, down: true)
        try await window.pointer(90, 40, down: false)
        XCTAssertEqual(changed, [])
        XCTAssertEqual(ended, [90])
    }
}
