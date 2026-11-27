import SwiftUI
import XCTest
#if os(Linux)
@testable import SwiftUI
import QtBridge
#else
import AppKit
#endif

@MainActor private final class MoveLog {
    var events: [String] = []
    var focus: ((Int) -> Void)?
}

private struct MoveTargets: View {
    @FocusState private var target: Int?
    @State private var text = "abcd"
    let log: MoveLog
    var body: some View {
        VStack {
            Color.blue.frame(width: 80, height: 24).focusable(interactions: .edit).focused($target, equals: 1)
                .onMoveCommand { log.events.append("inner " + String(describing: $0)) }
            Color.red.frame(width: 80, height: 24).focusable(interactions: .edit).focused($target, equals: 2)
                .onMoveCommand(perform: nil)
            Color.green.frame(width: 80, height: 24).focusable(interactions: .edit).focused($target, equals: 4)
            ScrollView {
                Button("Choose") {}.focused($target, equals: 5)
                    .onMoveCommand { log.events.append("inner " + String(describing: $0)) }
                Color.clear.frame(height: 130)
            }.frame(height: 44)
            TextField("Message", text: $text).focused($target, equals: 3).onMoveCommand { log.events.append("field " + String(describing: $0)) }
        }
        .onMoveCommand { log.events.append("outer " + String(describing: $0)) }
        .onAppear { log.focus = { target = $0 } }
    }
}

final class MoveCommandTests: XCTestCase {
    @MainActor func testFocusedMoveRouting() async throws {
        let log = MoveLog()
        let view = try await ScreenWindow(MoveTargets(log: log), width: 180, height: 175, keyboard: true)
        defer { view.close() }
        let focus = try XCTUnwrap(log.focus)
        for target in [1, 2, 4, 3, 5, 1] {
            focus(target)
            try await view.settle()
            log.events = []
            #if os(Linux)
            for key in ["Left", "Shift+Right", "Down", "Ctrl+Up", "Right", "Up"] {
                _ = qs_send_key_sequence(view.host.window, key)
            }
            #else
            let keys: [(Int, UInt16, NSEvent.ModifierFlags)] = [(0xf702, 123, []), (0xf703, 124, .shift),
                (0xf701, 125, []), (0xf700, 126, .control), (0xf703, 124, []), (0xf700, 126, [])]
            for (scalar, code, flags) in keys {
                let characters = String(UnicodeScalar(scalar)!)
                for type in [NSEvent.EventType.keyDown, .keyUp] {
                    let event = try XCTUnwrap(NSEvent.keyEvent(with: type, location: .zero,
                        modifierFlags: flags.union([.numericPad, .function]), timestamp: ProcessInfo.processInfo.systemUptime,
                        windowNumber: view.window.windowNumber, context: nil, characters: characters,
                        charactersIgnoringModifiers: characters, isARepeat: false, keyCode: code))
                    view.window.sendEvent(event)
                }
            }
            #endif
            let label = [1, 5].contains(target) ? "inner" : "outer"
            let expected = [1, 4, 5].contains(target) ? ["left", "down", "right", "up"].map { label + " " + $0 } : []
            XCTAssertEqual(log.events, expected, "Focused target \(target)")
        }
    }
}
