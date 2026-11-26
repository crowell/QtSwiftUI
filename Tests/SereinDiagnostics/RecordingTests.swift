import XCTest
import SwiftUI
import SignalI18n
@testable import CallDiagnostics
#if os(Linux)
import QtBridge
@testable import SwiftUI
#else
import AppKit
#endif

@Observable private final class RecordingSession {
    var start = Date.now.addingTimeInterval(-83)
    var timeouts = 0
    var drafts = 0
    var cancels = 0
    var sends = 0
}

private struct RecordingFixture: View {
    let session: RecordingSession
    var body: some View {
        CompositionRecording(peaks: RecordingPreview.peaks, startedAt: session.start,
                             onCancel: { session.cancels += 1 }, onSend: { session.sends += 1 },
                             errorRecording: { if $0 == .timeout { session.timeouts += 1 } },
                             saveDraftRecordingIfNeeded: { session.drafts += 1 })
            .environment(\.conversationListNow, session.start.addingTimeInterval(83))
            .frame(width: 640, height: 84).background(AxoColor.surfacePrimary)
    }
}

final class RecordingTests: XCTestCase {
    @MainActor func testVoiceNoteRendering() async throws {
        let screen = RecordingFixture(session: RecordingSession()).environment(\.colorScheme, .light)
        #if os(Linux)
        let host = Host(title: "Voice message") { screen.resolve($0) }
        host.open(width: 640, height: 84)
        defer { host.close() }
        XCTAssertEqual(qs_read_text(host.window, nil, "1:23"), 1)
        func red(_ x: Int, _ y: Int) -> Int { Int(qs_pixel(host.window, Int32(x), Int32(y)) >> 16 & 255) }
        #else
        let image = NSBitmapImageRep(cgImage: try XCTUnwrap(ImageRenderer(content: screen).cgImage))
        if let path = ProcessInfo.processInfo.environment["QTSWIFTUI_RECORDING_REFERENCE"] {
            try XCTUnwrap(image.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: path))
        }
        func red(_ x: Int, _ y: Int) -> Int { Int(image.colorAt(x: x, y: y)!.redComponent * 255) }
        #endif
        XCTAssertLessThan(red(604, 32), 160, "Send button fill")
        let centerInk = (220..<460).filter { red($0, 42) < 180 }.count
        XCTAssertGreaterThan(centerInk, 60, "Recorded peak bars")
        XCTAssertLessThan(centerInk, 180, "Spacing between bars")
        XCTAssertGreaterThan(red(160, 42), 210)
    }

    #if os(Linux)
    @MainActor func testDiscardDialogActions() async {
        var cancels = 0, discards = 0
        let strings = Localizer(locale: "en")
        let modal = AxoBaseDialog.Host {
            DiscardDraftDialog(onClose: { cancels += 1 }, onDiscard: { discards += 1 })
        }
        let host = Host(title: "Recording draft") { modal.resolve($0) }
        host.open(width: 520, height: 280)
        defer { host.close() }
        XCTAssertEqual(qs_read_text(host.window, nil, strings("icu:DiscardDraftDialog__description")), 1)
        XCTAssertEqual(qs_click_named_button(host.window, strings("icu:cancel")), 1)
        XCTAssertEqual(cancels, 1)
        XCTAssertEqual(discards, 0)
        XCTAssertEqual(qs_click_named_button(host.window, strings("icu:discard")), 1)
        XCTAssertEqual(discards, 1)
    }
    #endif

    @MainActor func testDraftAndTimeoutLifecycle() async throws {
        let session = RecordingSession()
        let screen = RecordingFixture(session: session)
        XCTAssertEqual(EnvironmentValues().scenePhase, .background)
        XCTAssertTrue(ScenePhase.background < .inactive && ScenePhase.inactive < .active)
        #if os(Linux)
        let host = Host(title: "Record") { screen.resolve($0) }
        host.open(width: 640, height: 84)
        defer { host.close() }
        let strings = Localizer(locale: "en")
        for (key, count) in [("icu:RecordingComposer__send", \RecordingSession.sends), ("icu:RecordingComposer__cancel", \.cancels)] {
            XCTAssertEqual(qs_click_named_button(host.window, strings(key)), 1)
            XCTAssertEqual(session[keyPath: count], 1)
        }
        _ = qs_key_escape(host.window)
        XCTAssertEqual(session.cancels, 2)
        qs_minimize(host.window, 1)
        qs_flush()
        XCTAssertEqual(qs_scene_phase(host.window), 0)
        qs_minimize(host.window, 0)
        qs_flush()
        #else
        let hosting = NSHostingView(rootView: screen)
        let window = NSWindow(contentRect: .init(x: 0, y: 0, width: 640, height: 84), styleMask: [.titled], backing: .buffered, defer: false)
        window.contentView = hosting
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }
        hosting.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(30))
        NotificationCenter.default.post(name: NSApplication.didResignActiveNotification, object: NSApp)
        #endif
        XCTAssertEqual(session.drafts, 1)
        // The near-expiry task must be cancelled when the recording is replaced.
        session.start = Date.now.addingTimeInterval(-3599.75)
        try await settle(milliseconds: 50)
        session.start = .now
        try await settle(milliseconds: 300)
        XCTAssertEqual(session.timeouts, 0)
        session.start = Date.now.addingTimeInterval(-3601)
        try await settle(milliseconds: 100)
        XCTAssertEqual(session.timeouts, 1)
    }

    @MainActor private func settle(milliseconds: Int) async throws {
        for _ in 0..<milliseconds / 10 {
            try await Task.sleep(for: .milliseconds(10))
            #if os(Linux)
            qs_flush()
            #endif
        }
    }
}
