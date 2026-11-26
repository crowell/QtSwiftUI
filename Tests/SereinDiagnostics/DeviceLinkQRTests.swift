import SwiftUI
import XCTest
@testable import CallDiagnostics

final class DeviceLinkQRTests: XCTestCase {
    @MainActor func testHelpUsesTheDesktopURLAction() async throws {
        var opened: [URL] = []
        let view = DeviceLinkQRPreview()
            .environment(\.openURL, OpenURLAction { opened.append($0); return .handled })
        let window = try await ScreenWindow(view, width: 880, height: 610)
        defer { window.close() }
        try await window.click(415, 378)
        XCTAssertEqual(opened, [InstallScreenQrCodeNotScannedStep.supportPage])
    }

    @MainActor func testRetryAfterProvisioningTimeout() async throws {
        var retries = 0
        let view = InstallScreenQrCodeNotScannedStep(provisioningUrl: .loadFailed(.timeout), retryGetQrCode: { retries += 1 })
        let window = try await ScreenWindow(view, width: 880, height: 610)
        defer { window.close() }
        try window.capture("link-qr-retry.png", directoryVariable: "QTSWIFTUI_QR_REFERENCE")
        try await window.click(220, 344)
        XCTAssertEqual(retries, 1)
    }
}
