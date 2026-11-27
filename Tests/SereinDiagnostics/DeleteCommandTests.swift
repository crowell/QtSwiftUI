import XCTest
#if os(Linux)
@_spi(Qt) @testable import SwiftUI
import QtBridge
#else
import SwiftUI
import AppKit
#endif

@MainActor private final class DeleteLog {
    var handlers: [String] = []
    var focus: ((Int) -> Void)?
    var text: (() -> String)?
}

private struct DeleteTargets: View {
    @FocusState var focused: Int?
    @State var text = "Draft"
    let log: DeleteLog

    var body: some View {
        VStack {
            Color.blue.frame(height: 20).focusable(interactions: .edit).focused($focused, equals: 1)
                .onDeleteCommand { log.handlers.append("inner") }
            Color.red.frame(height: 20).focusable(interactions: .edit).focused($focused, equals: 2)
                .onDeleteCommand(perform: nil)
            Color.green.frame(height: 20).focusable(interactions: .edit).focused($focused, equals: 3)
            TextField("Caption", text: $text).focused($focused, equals: 4)
                .onDeleteCommand { log.handlers.append("field") }
        }
        .onDeleteCommand { log.handlers.append("outer") }
        .onAppear {
            log.focus = { focused = $0 }
            log.text = { text }
        }
    }
}

final class DeleteCommandTests: XCTestCase {
    @MainActor func testFocusedKeyboardAndSystemDeletion() async throws {
        let log = DeleteLog()
        let screen = try await ScreenWindow(DeleteTargets(log: log), width: 220, height: 140, keyboard: true)
        defer { screen.close() }
        let focus = try XCTUnwrap(log.focus)
        for target in [1, 2, 3, 4, 1] {
            focus(target)
            try await screen.settle()
            log.handlers.removeAll()
            #if os(Linux)
            for key in ["Backspace", "Delete", "Alt+Backspace", "Shift+Backspace", "Shift+Delete", "Ctrl+Backspace"] {
                _ = qs_send_key_sequence(screen.host.window, key)
            }
            #else
            let keys: [(Int, UInt16, NSEvent.ModifierFlags)] = [(0x7f, 51, []), (0xf728, 117, .function),
                (0x7f, 51, .option), (0x7f, 51, .shift), (0xf728, 117, [.function, .shift]), (0x7f, 51, .control)]
            for (scalar, code, flags) in keys {
                let characters = String(UnicodeScalar(scalar)!)
                for type in [NSEvent.EventType.keyDown, .keyUp] {
                    let event = try XCTUnwrap(NSEvent.keyEvent(with: type, location: .zero, modifierFlags: flags,
                        timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: screen.window.windowNumber,
                        context: nil, characters: characters, charactersIgnoringModifiers: characters,
                        isARepeat: false, keyCode: code))
                    screen.window.sendEvent(event)
                }
            }
            #endif
            let handler = target == 1 ? "inner" : "outer"
            let enabled = target == 1 || target == 3
            XCTAssertEqual(log.handlers, enabled ? Array(repeating: handler, count: 4) : [], "Focused target \(target)")
            if target == 4 {
                try await screen.settle()
                XCTAssertNotEqual(log.text?(), "Draft", "The text field must receive its editing keys")
            }
            #if os(Linux)
            log.handlers.removeAll()
            XCTAssertEqual(QtDesktop.perform(.delete), target != 2)
            XCTAssertEqual(log.handlers, enabled ? [handler] : [])
            #endif
        }
    }
}
