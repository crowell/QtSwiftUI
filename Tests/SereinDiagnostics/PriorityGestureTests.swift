import XCTest
import SwiftUI
#if os(Linux)
import QtBridge
@testable import SwiftUI
#else
import AppKit
#endif

final class PriorityGestureTests: XCTestCase {
    @MainActor func testParentTapPrecedesButtonAndChildTap() async throws {
        for button in [false, true] {
            for mask: GestureMask in [.all, .none, .subviews, .gesture] {
                var events: [String] = []
                let child = button ? AnyView(Button("Open") { events.append("child") })
                                   : AnyView(Color.orange.onTapGesture { events.append("child") })
                let view = child.highPriorityGesture(TapGesture().onEnded { events.append("parent") }, including: mask)
                let screen = try await ScreenWindow(view, width: 120, height: 60)
                defer { screen.close() }
                try await screen.click(60, 30)
                XCTAssertEqual(events, [mask.contains(.gesture) ? "parent" : "child"])
            }
        }
    }

    @MainActor func testNamedGesturesPreserveOrderingAndEnablement() async throws {
        for enabled in [false, true] {
            var hits: [String] = []
            let view = Color.orange
                .gesture(TapGesture().onEnded { hits.append("inner") }, name: "Open item")
                .highPriorityGesture(TapGesture().onEnded { hits.append("high") }, name: "Inspect item", isEnabled: enabled)
                .simultaneousGesture(TapGesture().onEnded { hits.append("observe") }, name: "Observe selection")
            let screen = try await ScreenWindow(view, width: 120, height: 60)
            defer { screen.close() }
            try await screen.click(60, 30)
            XCTAssertEqual(hits, ["observe", enabled ? "high" : "inner"])
        }
    }

    #if os(Linux)
    @MainActor func testX11DoubleClickPrecedesNativeButtonOnPlatformInput() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["QTSWIFTUI_X11_DRAG"] == "1" &&
                          ProcessInfo.processInfo.environment["QT_QPA_PLATFORM"] == "xcb")
        var hits: [String] = []
        let view = Button("Open") { hits.append("button") }
            .highPriorityGesture(TapGesture(count: 2).onEnded { hits.append("double") })
        let screen = try await ScreenWindow(view, width: 120, height: 60)
        defer { screen.close() }
        let frame = qs_window_frame(screen.host.window), scale = qs_window_scale(screen.host.window)
        func clicks(_ count: Int) throws {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/xdotool")
            process.arguments = ["mousemove", String(Int((frame.x + 60) * scale)), String(Int((frame.y + 30) * scale)),
                                 "click", "--repeat", String(count), "--delay", "60", "1"]
            try process.run()
            process.waitUntilExit()
            XCTAssertEqual(process.terminationStatus, 0)
        }
        try clicks(1)
        for _ in 0..<70 where hits.isEmpty { try await screen.settle() }
        XCTAssertEqual(hits, ["button"])
        try clicks(2)
        for _ in 0..<70 where hits.count == 1 { try await screen.settle() }
        XCTAssertEqual(hits, ["button", "double"])
    }
    #endif

    @MainActor func testNestedPriorityAndDisabledFallback() async throws {
        for enabled in [true, false] {
            var events: [String] = []
            let view = VStack {
                Button("Open") { events.append("button") }
                    .highPriorityGesture(TapGesture().onEnded { events.append("inner") })
            }.highPriorityGesture(TapGesture().onEnded { events.append("outer") }, isEnabled: enabled)
            let screen = try await ScreenWindow(view, width: 120, height: 60)
            defer { screen.close() }
            try await screen.click(60, 30)
            XCTAssertEqual(events, [enabled ? "outer" : "inner"])
        }
    }

    @MainActor func testPriorityDragFallsBackToButtonAndChildDrag() async throws {
        for button in [false, true] {
            var events: [String] = []
            let child = button ? AnyView(Button("Open") { events.append("button") })
                : AnyView(Color.orange.gesture(DragGesture(minimumDistance: 2).onEnded { _ in events.append("short") }))
            let view = child.highPriorityGesture(DragGesture(minimumDistance: 45).onEnded { _ in events.append("long") })
            let screen = try await ScreenWindow(view, width: 120, height: 60)
            defer { screen.close() }
            try await screen.click(60, 30)
            try await screen.drag(from: CGPoint(x: 60, y: 30), to: CGPoint(x: 68, y: 30))
            try await screen.drag(from: CGPoint(x: 60, y: 30), to: CGPoint(x: 115, y: 30))
            XCTAssertEqual(events, button ? ["button", "button", "long"] : ["short", "long"])
        }
    }

    @MainActor func testSimultaneousAttachmentInsideAndOutsidePriority() async throws {
        for outerObserver in [false, true] {
            var hits: [String] = []
            let button = Button("Open") { hits.append("button") }
            let priority = TapGesture().onEnded { hits.append("high") }
            let simultaneous = TapGesture().onEnded { hits.append("simultaneous") }
            let view = outerObserver ? AnyView(button.highPriorityGesture(priority).simultaneousGesture(simultaneous))
                                     : AnyView(button.simultaneousGesture(simultaneous).highPriorityGesture(priority))
            let screen = try await ScreenWindow(view, width: 120, height: 60)
            defer { screen.close() }
            try await screen.click(60, 30)
            XCTAssertEqual(hits, ["simultaneous", outerObserver ? "high" : "button"])
        }
    }

    @MainActor func testSimultaneousDragFallsBackToEnclosingPriorityTap() async throws {
        var hits: [String] = []
        let view = Button("Open") { hits.append("button") }
            .simultaneousGesture(DragGesture(minimumDistance: 10).onEnded { _ in hits.append("drag") })
            .highPriorityGesture(TapGesture().onEnded { hits.append("high") })
        let screen = try await ScreenWindow(view, width: 120, height: 60)
        defer { screen.close() }
        try await screen.click(60, 30)
        try await screen.drag(from: CGPoint(x: 60, y: 30), to: CGPoint(x: 115, y: 30))
        XCTAssertEqual(hits, ["high", "drag"])
    }

    @MainActor func testPinchPriorityWithEqualAndDifferentThresholds() async throws {
        for outer in [0.01, 0.18] {
            var values: [String] = []
            let child = MagnifyGesture(minimumScaleDelta: 0.01)
                .onChanged { values.append("i" + String(Int(round($0.magnification * 100)))) }
                .onEnded { _ in values.append("iend") }
            let parent = MagnifyGesture(minimumScaleDelta: outer)
                .onChanged { values.append("o" + String(Int(round($0.magnification * 100)))) }
                .onEnded { _ in values.append("oend") }
            let screen = try await ScreenWindow(Color.red.gesture(child).highPriorityGesture(parent), width: 100, height: 60)
            defer { screen.close() }
            try await screen.pinch(at: CGPoint(x: 50, y: 30), factors: [1.04, 1.21, 1.30])
            XCTAssertEqual(values, outer == 0.01 ? ["o104", "o121", "o130", "oend"]
                : ["i104", "o121", "i121", "o130", "i130", "oend", "iend"])
        }
    }

    @MainActor func testSingleClickFallsBackAfterDoubleClickInterval() async throws {
        for button in [false, true] {
            var events: [String] = []
            let child = button ? AnyView(Button("Open") { events.append("single") })
                               : AnyView(Color.orange.onTapGesture { events.append("single") })
            let view = child.highPriorityGesture(TapGesture(count: 2).onEnded { events.append("double") })
            let screen = try await ScreenWindow(view, width: 120, height: 60)
            defer { screen.close() }
            try await screen.click(60, 30)
            XCTAssertTrue(events.isEmpty)
            for _ in 0..<70 where events.isEmpty { try await screen.settle() }
            XCTAssertEqual(events, ["single"])
            #if os(Linux)
            try await screen.click(60, 30)
            try await screen.click(60, 30)
            #else
            for count in 1...2 {
                for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                    screen.tick += 1
                    let ev = try XCTUnwrap(NSEvent.mouseEvent(with: type, location: CGPoint(x: 60, y: 30),
                        modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: screen.window.windowNumber,
                        context: nil, eventNumber: screen.tick, clickCount: count, pressure: type == .leftMouseUp ? 0 : 1))
                    NSApp.sendEvent(ev)
                }
            }
            try await screen.settle()
            #endif
            XCTAssertEqual(events, ["single", "double"])
        }
    }
}
