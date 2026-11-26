import SwiftUI
import XCTest
@testable import CallDiagnostics
#if os(Linux)
import QtBridge
#else
import AppKit
#endif

final class CallSurveyTests: XCTestCase {
    @MainActor func testPositiveRatingSkipsIssuesAndLeavesLogSharingOff() async throws {
        var result: CallQualitySurveyForm?
        let survey = AxoBaseDialog.Host { CallQualitySurveyDialog(onSubmit: { result = $0 }) }
        let window = try await ScreenWindow(survey, width: 520, height: 600)
        defer { window.close() }
        try await window.click(328, 321)
        try await window.click(90, 205) // Back returns to the rating page after a positive response.
        XCTAssertNil(result)
        try await window.click(328, 321)
        try await window.click(409, 394)
        let form = try XCTUnwrap(result)
        XCTAssertTrue(form.userSatisfied)
        XCTAssertTrue(form.callQualityIssues.isEmpty)
        XCTAssertEqual(form.additionalIssuesDescription, "")
        XCTAssertFalse(form.shareDebugLog)
    }

    @MainActor func testIssueReport() async throws {
        var forms: [CallQualitySurveyForm] = []
        var diagnosticOpens = 0, logOpens = 0
        let screen = AxoBaseDialog.Host {
            CallQualitySurveyDialog(onSubmit: { forms.append($0) }, onViewDebugLog: { logOpens += 1 },
                                    onViewDiagnosticInfo: { diagnosticOpens += 1 })
        }.background(AxoColor.surfacePrimary)
        let window = try await ScreenWindow(screen, width: 520, height: 600)
        defer { window.close() }
        func capture(_ stage: String) throws {
            try window.capture("call-survey-\(stage).png", directoryVariable: "QTSWIFTUI_SURVEY_REFERENCE")
        }
        try window.capture("call-quality-survey.png", directoryVariable: "QTSWIFTUI_SURVEY_REFERENCE")
        try await window.click(191, 321)
        try await window.click(400, 374) // Continue is disabled until an issue is selected.
        try await window.click(324, 333)
        try await window.click(120, 305)
        let report = "Audio lagged after reconnecting.\nIt lasted five seconds."
        try await window.type(report)
        try capture("feedback")
        try await window.click(400, 449)
        try capture("confirm")
        try await window.click(118, 238) // Plain text in the same attributed string.
        XCTAssertEqual(diagnosticOpens, 0)
        try await window.click(145, 254) // Second line of the diagnostic link.
        XCTAssertEqual(diagnosticOpens, 1)
        try await window.click(411, 307)
        XCTAssertEqual(logOpens, 1)
        try await window.click(92, 307)
        try await window.click(409, 394)
        let form = try XCTUnwrap(forms.first)
        XCTAssertEqual(forms.count, 1)
        XCTAssertFalse(form.userSatisfied)
        XCTAssertEqual(form.callQualityIssues, [.other])
        XCTAssertEqual(form.additionalIssuesDescription, report)
        XCTAssertTrue(form.shareDebugLog)
    }
}
