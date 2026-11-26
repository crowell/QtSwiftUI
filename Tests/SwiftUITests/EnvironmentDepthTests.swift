import XCTest
import QtBridge
@testable import SwiftUI

private enum RowDepth: EnvironmentKey { static let defaultValue = 0 }
private extension EnvironmentValues {
    var rowDepth: Int {
        get { self[RowDepth.self] }
        set { self[RowDepth.self] = newValue }
    }
}

private struct NestedRow: View {
    @Environment(\.rowDepth) private var inherited
    let remaining: Int

    var body: some View {
        if remaining == 0 {
            Text(verbatim: String(inherited)).accessibilityIdentifier("nested")
        } else {
            AnyView(NestedRow(remaining: remaining - 1).environment(\.rowDepth, inherited + 1))
        }
    }
}

private struct OutsideRow: View {
    @Environment(\.rowDepth) var inherited
    var body: some View { Text(verbatim: String(inherited)).accessibilityIdentifier("outside") }
}

final class EnvironmentDepthTests: XCTestCase {
    @MainActor func testDeeplyNestedOverridesStayLocalToTheirRow() async {
        let host = Host(title: "Nested environment") { ctx in
            VStack {
                NestedRow(remaining: 600)
                OutsideRow()
            }.environment(\.rowDepth, 1).resolve(ctx)
        }
        host.open(width: 160, height: 80)
        defer { host.close() }
        XCTAssertEqual(qs_read_text(host.window, "nested", "601"), 1)
        XCTAssertEqual(qs_read_text(host.window, "outside", "1"), 1)
    }
}
