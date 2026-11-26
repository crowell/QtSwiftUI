import XCTest
import SwiftUI
@testable import CallDiagnostics

final class CallLinkScreenTests: XCTestCase {
    @MainActor func testDetailsApprovalCopyAndRename() async throws {
        let model = CallLinkModel()
        var copied = "", joined = 0, shared = 0
        model.onCopy = { copied = $0 }
        model.onShare = { shared += 1 }
        model.onJoin = { joined += 1 }
        let window = try await ScreenWindow(CallLinkPreview(model: model), width: 620, height: 620)
        defer { window.close() }
        try window.capture("call-link.png", directoryVariable: "QTSWIFTUI_LINK_SCREENS")
        try await window.click(548, 60)
        try await window.click(115, 437)
        try await window.click(115, 472)
        XCTAssertEqual(copied, CallLinkModel.admin.webURL)
        XCTAssertEqual(joined, 1)
        XCTAssertEqual(shared, 1)
        try await window.click(550, 376)
        XCTAssertEqual(model.link?.requiresAdminApproval, true)
        model.activeOnServer = true
        try await window.settle()
        try await window.click(550, 376)
        XCTAssertEqual(model.link?.requiresAdminApproval, true)
        try await window.click(104, 342)
        XCTAssertEqual(model.dialog, .rename)
        try await window.settle()
        try window.capture("call-link-rename.png", directoryVariable: "QTSWIFTUI_LINK_SCREENS")
        try await window.click(428, 392)
        XCTAssertEqual(model.dialog, .rename)
        try await window.click(395, 347)
        try await window.type(" weekly  ")
        try await window.click(428, 392)
        XCTAssertNil(model.dialog)
        XCTAssertEqual(model.link?.name, "Admin Link weekly")
        try await window.click(104, 342)
        try await window.click(395, 347)
        try await window.type("discard")
        try await window.click(356, 392)
        XCTAssertNil(model.dialog)
        XCTAssertEqual(model.link?.name, "Admin Link weekly")
    }

    @MainActor func testHistoryOpensDetailsAndLinkManager() async throws {
        let history = CallHistoryModel(), created = CallLinkModel()
        let window = try await ScreenWindow(CallHistoryBrowserPreview(history: history, created: created), width: 360, height: 418)
        defer { window.close() }
        try await window.click(104, 304)
        guard case .callLink = history.selected else { return XCTFail("Call link row should open its details") }
        try await window.click(33, 26)
        XCTAssertNil(history.selected)
        try await window.click(121, 64)
        XCTAssertEqual(created.dialog, .manage)
        try window.capture("call-link-manager.png", directoryVariable: "QTSWIFTUI_LINK_SCREENS")
    }

    @MainActor func testNicknameMultilinePasteAndSave() async throws {
        var saved: NicknameAndNote?, closed = 0
        let screen = AxoBaseDialog.Host {
            EditNicknameAndNoteModal(avatar: .init(title: "Sam Rivera", color: "A170"),
                nicknameAndNote: .init(givenName: "Sam", note: "Prefers video calls."),
                onSave: { saved = $0 }, onClose: { closed += 1 })
        }.background(AxoColor.surfacePrimary)
        let window = try await ScreenWindow(screen, width: 520, height: 560)
        defer { window.close() }
        try window.capture("nickname-and-note.png", directoryVariable: "QTSWIFTUI_LINK_SCREENS")
        try await window.click(376, 448)
        XCTAssertNil(saved)
        try await window.click(243, 387)
        try await window.settle()
        try await window.click(290, 382)
        try await window.type("\nCall after 5 ☎")
        try await window.click(376, 448)
        XCTAssertEqual(saved?.givenName, "Sam")
        XCTAssertEqual(saved?.note, "Prefers video calls.\nCall after 5 ☎")
        XCTAssertEqual(closed, 1)
    }
}
