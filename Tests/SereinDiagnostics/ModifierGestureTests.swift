import XCTest
#if os(Linux)
@testable import SwiftUI
import QtBridge
#else
import SwiftUI
import AppKit
#endif

final class ModifierGestureTests: XCTestCase {
    private enum Phase: Int { case down, move, up }

    @MainActor private func pointer(_ phase: Phase, x: Int, modifiers: EventModifiers, count: Int = 1, in screen: ScreenWindow) throws {
        #if os(Linux)
        var prefix = ""
        for (flag, name): (EventModifiers, String) in [(.shift, "Shift"), (.control, "Ctrl"), (.option, "Alt"), (.command, "Meta")] {
            if modifiers.contains(flag) { prefix += name + "+" }
        }
        XCTAssertEqual(qs_modified_pointer(screen.host.window, Int32(x), 30, Int32(phase.rawValue), prefix + "A"), 1)
        #else
        var flags: NSEvent.ModifierFlags = []
        for (flag, native): (EventModifiers, NSEvent.ModifierFlags) in [(.shift,.shift), (.option,.option), (.control,.control), (.command,.command)] {
            if modifiers.contains(flag) { flags.insert(native) }
        }
        screen.tick += 1
        let type: NSEvent.EventType = phase == .down ? .leftMouseDown : phase == .move ? .leftMouseDragged : .leftMouseUp
        let event = try XCTUnwrap(NSEvent.mouseEvent(with: type, location: CGPoint(x: x, y: 30),
            modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime + Double(screen.tick) * 0.016,
            windowNumber: screen.window.windowNumber, context: nil, eventNumber: screen.tick, clickCount: count,
            pressure: phase == .up ? 0 : 1))
        NSApp.sendEvent(event)
        #endif
    }

    @MainActor func testTapRequiresAllNestedModifiersAtMouseDown() async throws {
        var taps = 0
        let gesture = TapGesture().modifiers(.shift).modifiers(.option).onEnded { taps += 1 }
        let screen = try await ScreenWindow(Color.orange.gesture(gesture), width: 100, height: 60)
        defer { screen.close() }
        for (down, up, expected): (EventModifiers, EventModifiers, Int) in [
            ([], [], 0), (.shift, [.shift, .option], 0), (.option, .option, 0),
            ([.shift, .option], [], 1), ([.shift, .option, .command], .command, 2)
        ] {
            try pointer(.down, x: 30, modifiers: down, in: screen)
            try pointer(.up, x: 30, modifiers: up, in: screen)
            try await screen.settle()
            XCTAssertEqual(taps, expected)
        }
    }

    @MainActor func testDoubleTapUsesModifiersFromFirstClick() async throws {
        for (first, second, expected): (EventModifiers, EventModifiers, Int) in [
            (.shift, .shift, 1), (.shift, [], 1), ([], .shift, 0), ([], [], 0)
        ] {
            var taps = 0
            let gesture = TapGesture(count: 2).modifiers(.shift).onEnded { taps += 1 }
            let screen = try await ScreenWindow(Color.orange.gesture(gesture), width: 100, height: 60)
            defer { screen.close() }
            for (i, flags) in [first, second].enumerated() {
                try pointer(.down, x: 30, modifiers: flags, count: i + 1, in: screen)
                try pointer(.up, x: 30, modifiers: flags, count: i + 1, in: screen)
            }
            try await screen.settle()
            XCTAssertEqual(taps, expected)
        }
    }

    @MainActor func testDragKeepsStartingModifiersThroughMotionAndRelease() async throws {
        var changes: [CGFloat] = [], ended: [CGFloat] = []
        let drag = DragGesture(minimumDistance: 10).modifiers(.shift)
            .onChanged { changes.append($0.location.x) }.onEnded { ended.append($0.location.x) }
        let screen = try await ScreenWindow(Color.orange.gesture(drag), width: 120, height: 60)
        defer { screen.close() }
        for down: EventModifiers in [[], .shift] {
            try pointer(.down, x: 15, modifiers: down, in: screen)
            let after: EventModifiers = down == .shift ? [] : .shift
            try pointer(.move, x: 40, modifiers: after, in: screen)
            try pointer(.move, x: 70, modifiers: after, in: screen)
            try pointer(.up, x: 90, modifiers: after, in: screen)
            try await screen.settle()
        }
        XCTAssertEqual(changes, [40, 70])
        XCTAssertEqual(ended, [90])
    }

    #if os(Linux)
    @MainActor func testX11LatchedCapsLockFiltersPointerGestures() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["QTSWIFTUI_X11_DRAG"] == "1" &&
                          ProcessInfo.processInfo.environment["QT_QPA_PLATFORM"] == "xcb")
        var taps = 0
        let view = Color.blue.gesture(TapGesture().modifiers(.capsLock).onEnded { taps += 1 })
        let screen = try await ScreenWindow(view, width: 80, height: 60)
        defer { screen.close() }
        func toggleLock() throws {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/xdotool")
            process.arguments = ["key", "Caps_Lock"]
            try process.run()
            process.waitUntilExit()
            XCTAssertEqual(process.terminationStatus, 0)
        }
        try await screen.click(40, 30)
        XCTAssertEqual(taps, 0)
        try toggleLock()
        defer { try? toggleLock() }
        try await screen.click(40, 30)
        XCTAssertEqual(taps, 1)
    }
    #endif
}
