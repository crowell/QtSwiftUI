import XCTest
import QtBridge
@testable import SwiftUI

private extension EnvironmentValues {
    @Entry var diagnosticTitle: String = "Default"
    @Entry var diagnosticFlag = true
    @Entry var diagnosticNumber: Int?
}

final class DiagnosticAPITests: XCTestCase {
    func testEnvironmentEntryStorage() {
        var original = EnvironmentValues()
        XCTAssertTrue(original.diagnosticFlag)
        XCTAssertNil(original.diagnosticNumber)
        original.diagnosticNumber = 7
        var copy = original
        copy.diagnosticNumber = nil
        copy.diagnosticTitle = "Call"
        XCTAssertNil(copy.diagnosticNumber)
        XCTAssertEqual(original.diagnosticNumber, 7)
        XCTAssertEqual(original.diagnosticTitle, "Default")
        XCTAssertEqual(copy.diagnosticTitle, "Call")
    }

    func testQtMonospacedSelectableTextAndEscape() async {
        await MainActor.run {
            var closed = false
            let host = Host(title: "Diagnostics") { ctx in
                VStack {
                    Text("opus / 48000").font(.system(size: 12, design: .monospaced))
                        .textSelection(.enabled).accessibilityIdentifier("stats")
                    Button("Close") { closed = true }
                }.onExitCommand { closed = true }.resolve(ctx)
            }
            defer { host.close() }
            host.open(width: 260, height: 160)
            XCTAssertEqual(qs_fixed_font(host.window, "stats"), 1)
            XCTAssertEqual(qs_select_text(host.window, "stats", 0, 4, "opus"), 1)
            XCTAssertEqual(qs_key_escape(host.window), 1)
            XCTAssertTrue(closed)
        }
    }
}
