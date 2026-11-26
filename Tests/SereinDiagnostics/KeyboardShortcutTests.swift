import XCTest
@testable import CallDiagnostics
#if os(Linux)
import QtBridge
@testable import SwiftUI
#else
import AppKit
import SwiftUI
#endif

private struct ShortcutStyle: ButtonStyle {
    @Environment(\.keyboardShortcut) var shortcut
    func makeBody(configuration: Configuration) -> some View {
        Text(shortcut.map { "Shortcut " + String($0.key.character) } ?? "No shortcut")
    }
}

final class KeyboardShortcutTests: XCTestCase {
    func testValuesMatchTheSDK() {
        XCTAssertEqual([EventModifiers.capsLock, .shift, .control, .option, .command, .numericPad, .all].map(\.rawValue),
                       [1, 2, 4, 8, 16, 32, 63])
        let special: [KeyEquivalent] = [.upArrow, .downArrow, .leftArrow, .rightArrow, .escape, .delete, .deleteForward,
                                        .home, .end, .pageUp, .pageDown, .clear, .tab, .space, .return]
        XCTAssertEqual(special.map { $0.character.unicodeScalars.first!.value },
                       [63232, 63233, 63234, 63235, 27, 8, 63272, 63273, 63275, 63276, 63277, 63289, 9, 32, 13])
        XCTAssertEqual(KeyboardShortcut.cancelAction, KeyboardShortcut(.escape, modifiers: []))
        XCTAssertEqual(KeyboardShortcut.defaultAction, KeyboardShortcut(.return, modifiers: []))
        XCTAssertEqual(KeyboardShortcut("x").modifiers, .command)
        XCTAssertNotEqual(KeyboardShortcut("x"), KeyboardShortcut("x", localization: .custom))
    }

    @MainActor func testButtonStyleReadsTheAssignedShortcut() async {
        var seen: [KeyboardShortcut?] = []
        struct ReadingStyle: ButtonStyle {
            @Environment(\.keyboardShortcut) var shortcut
            let record: (KeyboardShortcut?) -> Void
            func makeBody(configuration: Configuration) -> some View {
                let _ = record(shortcut)
                configuration.label.opacity(shortcut == nil ? 0.5 : 1)
            }
        }
        let shortcut = KeyboardShortcut("v", modifiers: [.control, .shift])
        let control = Button("Answer") {}.buttonStyle(ReadingStyle { seen.append($0) }).keyboardShortcut(shortcut)
        #if os(Linux)
        let host = Host(title: "Button style") { control.resolve($0) }
        host.open(width: 180, height: 60)
        defer { host.close() }
        #else
        let host = NSHostingView(rootView: control)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 180, height: 60),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        func draw() {
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))
            _ = host.fittingSize
        }
        draw()
        defer { withExtendedLifetime(window) {} }
        #endif
        XCTAssertTrue(seen.contains(shortcut), "Button style saw \(seen.map { $0.map { String($0.key.character) + String($0.modifiers.rawValue) } ?? "nil" })")
    }

    #if os(Linux)
    @MainActor func testNativeShortcutsResolveInViewOrderAndUpdateWithState() async {
        var firstEnabled = true, key: KeyboardShortcut? = KeyboardShortcut("k", modifiers: [.control, .shift])
        var first = 0, second = 0, toggle = false
        func screen() -> some View {
            VStack {
                Button("First") { first += 1 }.buttonStyle(ShortcutStyle()).keyboardShortcut(key).disabled(!firstEnabled)
                Button("Second") { second += 1 }.keyboardShortcut("k", modifiers: [.control, .shift])
                Toggle("Capture", isOn: Binding(get: { toggle }, set: { toggle = $0 })).keyboardShortcut(.defaultAction)
            }
        }
        let host = Host(title: "Keys") { screen().resolve($0) }
        defer { host.close() }
        host.open(width: 240, height: 140)
        func send(_ sequence: String) { XCTAssertEqual(qs_send_key_sequence(host.window, sequence), 1) }
        func render() { host.update(); qs_flush() }
        XCTAssertEqual(qs_read_text(host.window, nil, "Shortcut k"), 1)
        send("Ctrl+Shift+K")
        send("Ctrl+K")
        XCTAssertEqual(first, 1)
        XCTAssertEqual(second, 0)
        firstEnabled = false
        render()
        send("Ctrl+Shift+K")
        XCTAssertEqual(second, 1)
        firstEnabled = true
        key = KeyboardShortcut("j")
        render()
        send("Ctrl+Shift+K")
        send("Meta+J")
        XCTAssertEqual(second, 2)
        XCTAssertEqual(first, 2)
        key = nil
        render()
        send("Meta+J")
        XCTAssertEqual(first, 2)
        XCTAssertEqual(qs_read_text(host.window, nil, "No shortcut"), 1)
        send("Return")
        XCTAssertTrue(toggle)
    }

    @MainActor func testHiddenSereinLobbyShortcutsDriveAudioAndVideo() async {
        var video = false, audio = true
        let host = Host(title: "Call lobby") { context in
            LobbyKeyboardControls(hasLocalVideo: video, hasLocalAudio: audio,
                                  setLocalVideo: { video = $0 }, setLocalAudio: { audio = $0 }).resolve(context)
        }
        defer { host.close() }
        host.open(width: 200, height: 80)
        _ = qs_send_key_sequence(host.window, "Shift+M")
        XCTAssertFalse(audio)
        XCTAssertFalse(video)
        _ = qs_send_key_sequence(host.window, "Shift+V")
        XCTAssertTrue(video)
    }
    #endif
}
