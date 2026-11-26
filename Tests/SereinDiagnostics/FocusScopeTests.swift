import SwiftUI
import XCTest

private struct ScopedFields: View {
    @Namespace private var editor
    @Namespace private var other
    @Environment(\.resetFocus) private var reset
    @FocusState private var field: Int?
    let report: (Int?) -> Void
    let actions: (@escaping () -> Void, @escaping () -> Void) -> Void

    var body: some View {
        VStack {
            VStack {
                TextField("First", text: .constant("")).focused($field, equals: 1)
                TextField("Preferred", text: .constant("")).prefersDefaultFocus(in: editor)
                    .focused($field, equals: 2)
            }.focusScope(editor)
            TextField("Outside", text: .constant("")).focused($field, equals: 3)
                .prefersDefaultFocus(in: editor).focusScope(other)
        }
        .onAppear { actions({ field = 3 }, { reset(in: editor) }) }
        .onChange(of: field, initial: true) { _, value in report(value) }
    }
}

final class FocusScopeTests: XCTestCase {
    @MainActor func testResetMovesFocusAwayFromAnOutsideField() async throws {
        var selected: Int?
        var moveOutside: (() -> Void)?
        var restore: (() -> Void)?
        let view = ScopedFields(report: { selected = $0 }, actions: { moveOutside = $0; restore = $1 })
        let window = try await ScreenWindow(view, width: 220, height: 160, keyboard: true)
        defer { window.close() }
        try XCTUnwrap(moveOutside)()
        for _ in 0..<20 where selected != 3 { try await window.settle() }
        XCTAssertEqual(selected, 3)
        try XCTUnwrap(restore)()
        for _ in 0..<20 where selected == 3 { try await window.settle() }
        XCTAssertNotEqual(selected, 3)
        #if !os(Linux)
        // An inactive AppKit window releases its field editor. A key window
        // can deliver focus to the preferred field immediately.
        if !window.window.isKeyWindow { XCTAssertNil(selected); return }
        #endif
        for _ in 0..<20 where selected != 2 { try await window.settle() }
        XCTAssertEqual(selected, 2)
    }
}
