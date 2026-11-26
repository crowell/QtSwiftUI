import XCTest
import SwiftUI
#if os(Linux)
import QtBridge
@testable import SwiftUI
#else
import AppKit
#endif

// The SDK also permits installing the handler from a nonisolated view factory.
private func consumingKey<V: View>(_ view: V, record: @escaping (String, KeyPress) -> Void) -> some View {
    view.onKeyPress(phases: .all) { record("any", $0); return .handled }
}

private struct KeyTarget: View {
    @FocusState var focused: Bool
    let record: (String, KeyPress) -> Void
    var body: some View {
        consumingKey(Color.blue.frame(width: 40, height: 40).focusable().focused($focused), record: record)
            .onKeyPress(keys: ["a"], phases: [.down, .repeat]) { record("a", $0); return .handled }
            .onKeyPress(characters: .letters, phases: .all) { record("letters", $0); return .ignored }
            .onAppear { focused = true }
    }
}

final class KeyPressTests: XCTestCase {
    @MainActor func testFocusedFilteringAndIgnoredEvents() async throws {
        var sequence: [String] = []
        var output: [KeyPress] = []
        let view = KeyTarget { sequence.append($0); output.append($1) }
        #if os(Linux)
        let host = Host(title: "Keys") { view.resolve($0) }
        host.open(width: 40, height: 40)
        defer { host.close() }
        qs_flush()
        XCTAssertEqual(qs_send_repeated_key(host.window, "Shift+A", 1), 1)
        XCTAssertEqual(qs_send_key_sequence(host.window, "Shift+B"), 1)
        #else
        let hosting = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 40, height: 40), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = hosting
        window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        hosting.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(35))
        let inputs: [(String, NSEvent.EventType, Bool)] = [("a", .keyDown, false), ("a", .keyDown, true), ("a", .keyUp, false),
                                                          ("b", .keyDown, false), ("b", .keyUp, false)]
        for (letter, type, repeated) in inputs {
            let event = try XCTUnwrap(NSEvent.keyEvent(with: type, location: .zero, modifierFlags: .shift,
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, characters: letter.uppercased(), charactersIgnoringModifiers: letter,
                isARepeat: repeated, keyCode: letter == "a" ? 0 : 11))
            window.sendEvent(event)
        }
        #endif
        XCTAssertEqual(sequence, ["letters", "a", "letters", "a", "letters", "letters", "any", "letters", "any"])
        XCTAssertEqual(output.map(\.phase), [.down, .down, .repeat, .repeat, .up, .down, .down, .up, .up])
        XCTAssertEqual(output.map(\.characters), ["a", "a", "a", "a", "a", "b", "b", "b", "b"])
        for press in output {
            XCTAssertEqual(press.debugDescription, "KeyPress(\(press.phase.debugDescription), \(press.characters.debugDescription))")
            XCTAssertEqual(press.key, KeyEquivalent(try XCTUnwrap(press.characters.first)))
            XCTAssertTrue(press.modifiers.contains(.shift))
        }
    }
}
