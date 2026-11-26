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

@Observable private final class DraftPlayback {
    var playing = false
    var fraction = 32.0 / 83
}
private struct DraftFixture: View {
    let state: DraftPlayback
    var body: some View {
        CompositionRecordingDraft(peaks: RecordingPreview.peaks.map { $0.value / 255 }, duration: 83,
            active: .init(playing: state.playing, duration: 83, currentTime: state.fraction * 83),
            onPlay: { state.playing = true }, onPause: { state.playing = false }, onScrub: { state.fraction = $0 })
            .frame(width: 640, height: 84).background(AxoColor.surfacePrimary)
    }
}

final class RecordingDraftTests: XCTestCase {
    @MainActor func testProductionWaveformAndScrubbing() async throws {
        let state = DraftPlayback()
        let view = DraftFixture(state: state).environment(\.colorScheme, .light)
        #if os(Linux)
        let host = Host(title: "Draft") { view.resolve($0) }
        host.open(width: 640, height: 84)
        defer { host.close() }
        func red(_ x: Int) -> Int { Int(qs_pixel(host.window, Int32(x), 42) >> 16 & 255) }
        #else
        let bitmap = NSBitmapImageRep(cgImage: try XCTUnwrap(ImageRenderer(content: view).cgImage))
        if let path = ProcessInfo.processInfo.environment["QTSWIFTUI_DRAFT_REFERENCE"] {
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: path))
        }
        func red(_ x: Int) -> Int { Int(bitmap.colorAt(x: x, y: 42)!.redComponent * 255) }
        #endif
        XCTAssertTrue((35..<44).contains { red($0) < 64 })
        XCTAssertTrue((85..<95).contains { red($0) < 90 }, "Played bars")
        XCTAssertTrue((370..<385).contains { red($0) > 90 && red($0) < 180 }, "Remaining bars")
        #if os(Linux)
        let i18n = Localizer(locale: "en")
        XCTAssertEqual(qs_click_named_button(host.window, i18n("icu:MessageAudio--play")), 1)
        XCTAssertTrue(state.playing)
        try await Task.sleep(for: .milliseconds(15))
        qs_flush()
        XCTAssertEqual(qs_click_named_button(host.window, i18n("icu:MessageAudio--pause")), 1)
        XCTAssertFalse(state.playing)
        for x in [69, 169, 367, 461] {
            XCTAssertEqual(qs_click_point(host.window, Int32(x), 42), 1)
            XCTAssertEqual(state.fraction, Double(x - 68) / 395, accuracy: 0.006)
        }
        #endif
    }
}
