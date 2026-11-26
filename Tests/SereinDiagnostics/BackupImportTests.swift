import SwiftUI
import XCTest
import SignalI18n
@testable import CallDiagnostics
#if os(Linux)
@testable import SwiftUI
import QtBridge
#endif

final class BackupImportTests: XCTestCase {
    @MainActor func testDownloadProgressAndSecurityLink() async throws {
        var opened: [URL] = []
        let screen = InstallScreenBackupImportStep(step: .download(currentBytes: 23_000_000, totalBytes: 50_000_000),
                                                  openURL: { opened.append($0) })
        XCTAssertEqual(screen.fraction, 0.46)
        let window = try await ScreenWindow(screen.axoViewport(), width: 880, height: 610)
        defer { window.close() }
        try window.capture("backup-import.png", directoryVariable: "QTSWIFTUI_BACKUP_REFERENCE")
        // Sample the solid fill and track on either side of the 46% boundary.
        XCTAssertNotEqual(window.pixel(420, 259), window.pixel(435, 259))
        XCTAssertEqual(window.pixel(420, 259), window.pixel(300, 259))
        try await window.click(542, 505)
        XCTAssertEqual(opened, [InstallScreenBackupImportStep.securityURL])
    }

    @MainActor func testProgressStates() {
        XCTAssertNil(InstallScreenBackupImportStep(step: .waitForBackup).fraction)
        XCTAssertNil(InstallScreenBackupImportStep(step: .download(currentBytes: 12, totalBytes: 50), error: .canceled).fraction)
        XCTAssertEqual(InstallScreenBackupImportStep(step: .process(currentBytes: 2, totalBytes: 0)).fraction, 0)
        XCTAssertEqual(InstallScreenBackupImportStep(step: .process(currentBytes: 199, totalBytes: 200)).fraction, 0.99)
    }

    #if os(Linux)
    @MainActor func testCancelRequiresConfirmationAndReportsOneCallback() async throws {
        var cancels = 0
        let screen = InstallScreenBackupImportStep(step: .download(currentBytes: 23, totalBytes: 50), onCancel: { cancels += 1 })
        let window = try await ScreenWindow(screen.axoViewport(), width: 880, height: 610)
        defer { window.close() }
        let en = Localizer(locale: "en")
        func press(_ key: String) async throws {
            XCTAssertEqual(qs_click_named_button(window.host.window, en(key)), 1)
            try await window.settle()
        }
        try await press("icu:BackupImportScreen__cancel")
        XCTAssertEqual(cancels, 0)
        try await press("icu:BackupImportScreen__cancel-confirmation__cancel")
        try await press("icu:BackupImportScreen__cancel")
        try await press("icu:BackupImportScreen__cancel-confirmation__confirm")
        XCTAssertEqual(cancels, 1)
    }
    #endif
}
