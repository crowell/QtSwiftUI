import QtBridge
import XCTest
@testable import SwiftUI

private struct ScopedForm: View {
    @Namespace private var form
    @Namespace private var other
    @Environment(\.resetFocus) private var reset
    @State private var includePreferred = true

    var body: some View {
        VStack {
            TextField("Outside", text: .constant(""))
                .prefersDefaultFocus(in: form).accessibilityIdentifier("outside")
            VStack {
                TextField("First", text: .constant("")).accessibilityIdentifier("first")
                TextField("Disabled", text: .constant(""))
                    .disabled(true).prefersDefaultFocus(in: form).accessibilityIdentifier("disabled")
                if includePreferred {
                    TextField("Preferred", text: .constant("")).prefersDefaultFocus(in: form)
                        .accessibilityIdentifier("preferred")
                }
            }.focusScope(form)
            Button("Reset") { reset(in: form) }.accessibilityIdentifier("reset")
            Button("Remove") { includePreferred = false }.accessibilityIdentifier("remove")
            Button("Unknown scope") { reset(in: other) }.accessibilityIdentifier("unknown")
        }
    }
}

final class ScopedFocusTests: XCTestCase {
    @MainActor func testInitialPreferenceScopedResetAndRemoval() async {
        let host = Host(title: "Scopes") { ScopedForm().resolve($0) }
        host.open(width: 220, height: 240)
        defer { host.close() }
        XCTAssertEqual(qs_has_focus(host.window, "preferred"), 1)
        XCTAssertEqual(qs_click(host.window, "unknown"), 1)
        XCTAssertEqual(qs_has_focus(host.window, "preferred"), 1)
        XCTAssertEqual(qs_click(host.window, "reset"), 1)
        XCTAssertEqual(qs_has_focus(host.window, "preferred"), 1)
        XCTAssertEqual(qs_click(host.window, "remove"), 1)
        XCTAssertEqual(qs_click(host.window, "reset"), 1)
        XCTAssertEqual(qs_has_focus(host.window, "first"), 1)
    }
}
