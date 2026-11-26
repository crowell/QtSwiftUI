import QtBridge
import XCTest
@testable import SwiftUI

private struct FormRegion: View {
    @FocusState private var selection: Int?
    let priority: DefaultFocusEvaluationPriority
    let move: (@escaping (Int) -> Void) -> Void

    var body: some View {
        VStack {
            field(0)
            VStack {
                field(1)
                field(2)
                field(3)
            }.defaultFocus($selection, 2, priority: priority)
        }
        .onAppear { move { selection = $0 } }
    }

    private func field(_ index: Int) -> some View {
        TextField("Field", text: .constant("")).frame(height: 30).focused($selection, equals: index)
            .accessibilityIdentifier("field-\(index)")
    }
}

final class BindingFocusTests: XCTestCase {
    @MainActor func testInitialPreferenceAndKeyboardEntryPriorities() async throws {
        for (priority, entered) in [(DefaultFocusEvaluationPriority.automatic, 1), (.userInitiated, 2)] {
            var select: ((Int) -> Void)?
            let host = Host(title: "Focus region") { ctx in FormRegion(priority: priority) { select = $0 }.resolve(ctx) }
            host.open(width: 200, height: 180)
            defer { host.close() }
            XCTAssertEqual(qs_has_focus(host.window, "field-2"), 1)
            try XCTUnwrap(select)(0)
            qs_flush()
            XCTAssertEqual(qs_has_focus(host.window, "field-0"), 1)
            XCTAssertEqual(qs_tab(host.window), 1)
            qs_flush()
            XCTAssertEqual(qs_has_focus(host.window, "field-\(entered)"), 1)
            XCTAssertEqual(qs_tab(host.window), 1)
            XCTAssertEqual(qs_has_focus(host.window, "field-\(entered + 1)"), 1)
            try XCTUnwrap(select)(0)
            qs_flush()
            XCTAssertEqual(qs_click_point(host.window, 100, 71), 1)
            XCTAssertEqual(qs_has_focus(host.window, "field-1"), 1)
            try XCTUnwrap(select)(0)
            qs_flush()
            try XCTUnwrap(select)(1)
            qs_flush()
            qs_flush()
            XCTAssertEqual(qs_has_focus(host.window, "field-2"), 1)
        }
    }
}
