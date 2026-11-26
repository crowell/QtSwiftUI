import SignalI18n
import SwiftUI
import XCTest
@testable import CallDiagnostics
#if os(Linux)
import QtBridge
@testable import SwiftUI
#endif

final class CallParticipantTests: XCTestCase {
    @MainActor func testRaisedHandInvokesParticipantAction() async throws {
        var taps = 0
        let tile = GroupCallRemoteParticipant(participant: ParticipantPreview().speaker, width: 260, height: 180,
                                              inGrid: true, audioLevel: 0.6, onClickRaisedHand: { taps += 1 })
        let window = try await ScreenWindow(tile.environment(\.colorScheme, .dark), width: 260, height: 180)
        defer { window.close() }
        try await window.click(42, 156)
        XCTAssertEqual(taps, 1)
    }

    #if os(Linux)
    @MainActor func testBlockedParticipantOpensAndDismissesNativeAlert() async throws {
        let window = try await ScreenWindow(ParticipantPreview(), width: 556, height: 204)
        defer { window.close() }
        let en = Localizer(locale: "en")
        let title = en("icu:calling__block-info-title", ["name": .string(JoinRequestPreview.participant.title)])
        let message = en("icu:calling__block-info")
        for _ in 0..<2 {
            try await window.click(140, 134)
            XCTAssertEqual(qs_alert_response(window.host.window, title, message, "OK"), 1)
            try await window.settle()
            XCTAssertEqual(qs_alert_response(window.host.window, title, message, nil), 0)
        }
    }
    #endif
}
