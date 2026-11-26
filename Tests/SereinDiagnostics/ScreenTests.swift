import XCTest
import SignalI18n
@testable import CallDiagnostics
#if os(Linux)
import QtBridge
@testable import SwiftUI
#endif

final class ScreenTests: XCTestCase {
    @MainActor func testProductionReport() async throws {
        let formatted = CallDiagnosticWindow.format(DiagnosticContent.report)
        let report = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(formatted.utf8)) as? [String: Any])
        XCTAssertNil(report["rawStatsText"])
        let stats = try XCTUnwrap(report["rawStats"] as? [String: Any])
        let audio = try XCTUnwrap(stats["audio"] as? [String: Any])
        XCTAssertEqual(audio["codec"] as? String, "opus")
        XCTAssertEqual(CallDiagnosticWindow.format("Call ended"), "Call ended")
    }

    #if os(Linux)
    func testGermanWindowScrollAndClose() async {
        await MainActor.run {
            let german = Localizer(locale: "de")
            var closes = 0
            let host = Host(title: "Diagnostics") { context in
                CallDiagnosticWindow(diagnosticData: DiagnosticContent.report) { closes += 1 }
                    .environment(\.i18n, german)
                    .resolve(context)
            }
            defer { host.close() }
            host.open(width: 400, height: 220)
            let title = german("icu:CallDiagnosticWindow__title")
            XCTAssertNotEqual(title, Localizer(locale: "en")("icu:CallDiagnosticWindow__title"))
            XCTAssertEqual(qs_read_text(host.window, nil, title), 1)
            XCTAssertEqual(qs_uses_family(host.window, title, "Inter"), 1)
            XCTAssertEqual(qs_read_text(host.window, nil, CallDiagnosticWindow.format(DiagnosticContent.report)), 1)
            XCTAssertEqual(qs_scroll_to_end(host.window), 1)
            XCTAssertEqual(qs_click_named_button(host.window, german("icu:close")), 1)
            XCTAssertEqual(closes, 1)
            XCTAssertEqual(qs_key_escape(host.window), 1)
            XCTAssertEqual(closes, 2)
        }
    }
    #endif
}
