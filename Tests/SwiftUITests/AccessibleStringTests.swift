import QtBridge
import XCTest
@testable import SwiftUI

final class AccessibleStringTests: XCTestCase {
    @MainActor func testLabelValueAndNamedActionFollowTheEnvironmentLocale() async {
        let number = 1234.5
        var locale = Locale(identifier: "fr-FR")
        var actions = 0
        let host = SwiftUI.Host(title: "Accessibility") { context in
            Color.clear.frame(width: 64, height: 32)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Total \(number, format: .number)")
                .accessibilityLabel("Unused", isEnabled: false)
                .accessibilityValue("Balance \(number, format: .number)")
                .accessibilityValue("Unused", isEnabled: false)
                .accessibilityHint("Edit \(number, format: .number)")
                .accessibilityAction(named: "Choose \(number, format: .number)") { actions += 1 }
                .environment(\.locale, locale)
                .resolve(context)
        }
        defer { host.close() }
        host.open(width: 120, height: 80)
        for language in ["fr-FR", "en-US"] {
            locale = Locale(identifier: language)
            host.update()
            qs_flush()
            let amount = number.formatted(.number.locale(locale))
            XCTAssertEqual(qs_accessible_value_is(host.window, "Total " + amount, "Balance " + amount), 1)
            XCTAssertEqual(qs_accessible_element(host.window, "Total " + amount, 0, "Choose " + amount), 1)
        }
        XCTAssertEqual(actions, 2)
    }
}
