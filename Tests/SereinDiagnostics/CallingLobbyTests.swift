import XCTest
import SwiftUI
@testable import CallDiagnostics

final class CallingLobbyTests: XCTestCase {
    @MainActor func testMicrophoneRingAndStart() async throws {
        let model = LobbyPreviewModel()
        let screen = try await ScreenWindow(LobbyPreview(model: model), width: 900, height: 590)
        defer { screen.close() }
        try await screen.click(435, 534)
        XCTAssertFalse(model.audio)
        try await screen.click(491, 534)
        XCTAssertFalse(model.ring)
        try await screen.click(690, 534)
        XCTAssertTrue(model.connecting)
    }

    @MainActor func testHeaderButtons() async throws {
        for settings in [true, false] {
            let model = LobbyPreviewModel()
            let screen = try await ScreenWindow(LobbyPreview(model: model), width: 900, height: 590)
            defer { screen.close() }
            try await screen.click(settings ? 810 : 858, 50)
            XCTAssertEqual(model.settings, settings)
            XCTAssertEqual(model.cancelled, !settings)
        }
    }
}
