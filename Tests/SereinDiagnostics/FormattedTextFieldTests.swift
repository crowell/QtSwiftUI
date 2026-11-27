import SwiftUI
import XCTest
#if os(Linux)
@testable import SwiftUI
import QtBridge
#else
import AppKit
#endif

// SwiftUI places no Equatable or numeric constraint on a format style's input.
private struct Code { let number: Int }
private struct CodeFormat: ParseableFormatStyle, ParseStrategy {
    var parseStrategy: Self { self }
    func format(_ value: Code) -> String { "v" + String(value.number) }
    func parse(_ value: String) throws -> Code {
        guard value.hasPrefix("v"), let number = Int(value.dropFirst()) else { throw CocoaError(.formatting) }
        return Code(number: number)
    }
}

@MainActor private final class FieldActions {
    var focus: ((Bool) -> Void)?
    var change: ((Int) -> Void)?
    var read: (() -> Int?)?
    var submissions = 0
}

private struct CodeEntry: View {
    @State var required = Code(number: 12)
    @State var optional: Code?
    @State var count = 12
    @FocusState var focus: Int?
    let mode: Mode
    let actions: FieldActions
    enum Mode { case required, optional, number, constant }

    var body: some View {
        VStack {
            Color.orange.frame(height: 12).focusable(interactions: .edit).focused($focus, equals: 1)
            Group {
                switch mode {
                case .required:
                    TextField(value: $required, format: CodeFormat(), prompt: Text("v123")) {
                        HStack { Text("Code") }
                    }
                case .optional:
                    TextField("Optional code", value: $optional, format: CodeFormat())
                case .constant:
                    TextField("Fixed", value: .constant(12), format: .number)
                case .number:
                    TextField("Number?".dropLast(), value: $count, format: .number.locale(Locale(identifier: "en_US")))
                }
            }
            .textFieldStyle(.squareBorder)
            .accessibilityIdentifier("value").focused($focus, equals: 2)
            .onSubmit { actions.submissions += 1 }
            if mode == .constant { Text(String(count)) }
        }.onAppear {
            actions.focus = { focus = $0 ? 2 : 1 }
            actions.change = { n in
                switch mode {
                case .required: required = Code(number: n)
                case .optional: optional = Code(number: n)
                case .number, .constant: count = n
                }
            }
            actions.read = {
                switch mode {
                case .required: required.number
                case .optional: optional?.number
                case .number: count
                case .constant: 12
                }
            }
        }
    }
}

@MainActor private extension ScreenWindow {
    func expectValue(_ expected: String, line: UInt = #line) throws {
        #if os(Linux)
        XCTAssertEqual(qs_read_text(host.window, "value", expected), 1, "Expected field text \(expected.debugDescription)", line: line)
        #else
        func find(_ view: NSView) -> NSTextField? {
            (view as? NSTextField) ?? view.subviews.lazy.compactMap(find).first
        }
        let field = try XCTUnwrap(find(hosting))
        XCTAssertEqual(field.currentEditor()?.string ?? field.stringValue, expected, line: line)
        #endif
    }

    func replaceValue(_ raw: String) async throws {
        #if os(Linux)
        XCTAssertEqual(qs_send_key_sequence(host.window, "Ctrl+A"), 1)
        if raw.isEmpty { XCTAssertEqual(qs_send_key_sequence(host.window, "Backspace"), 1) }
        #else
        let editor = try XCTUnwrap(window.firstResponder as? NSTextView)
        editor.selectAll(nil)
        if raw.isEmpty { editor.deleteBackward(nil) }
        #endif
        if raw.isEmpty { try await settle() } else { try await type(raw) }
    }
}

final class FormattedTextFieldTests: XCTestCase {
    @MainActor func testRequiredValueKeepsInvalidDraftUntilEditingEnds() async throws {
        let a = FieldActions()
        let s = try await ScreenWindow(CodeEntry(mode: .required, actions: a), width: 220, height: 100, keyboard: true)
        defer { s.close() }
        a.focus?(true)
        try await s.settle()
        try s.expectValue("v12")
        a.change?(19)
        try await s.settle()
        try s.expectValue("v19")
        try await s.replaceValue("v0034")
        try s.expectValue("v0034")
        XCTAssertEqual(a.read?(), 34)
        try await s.replaceValue("v-")
        try s.expectValue("v-")
        XCTAssertEqual(a.read?(), 34)
        try await s.pressReturn()
        try s.expectValue("v34")
        XCTAssertEqual(a.submissions, 1)
        try await s.replaceValue("")
        try s.expectValue("")
        XCTAssertEqual(a.read?(), 34)
        a.focus?(false)
        try await s.settle()
        try await s.settle()
        try s.expectValue("v34")
        XCTAssertEqual(a.submissions, 1)
    }

    @MainActor func testOptionalValueClearsOnFailedParseAndTracksExternalChanges() async throws {
        let a = FieldActions()
        let s = try await ScreenWindow(CodeEntry(mode: .optional, actions: a), width: 220, height: 100, keyboard: true)
        defer { s.close() }
        a.focus?(true)
        try await s.settle()
        try s.expectValue("")
        try await s.replaceValue("v0007")
        XCTAssertEqual(a.read?(), 7)
        try s.expectValue("v0007")
        a.change?(9)
        try await s.settle()
        try s.expectValue("v9")
        try await s.replaceValue("pending")
        XCTAssertNil(try XCTUnwrap(a.read)())
        try s.expectValue("pending")
        try await s.pressReturn()
        try s.expectValue("")
        try await s.replaceValue("v27")
        try await s.replaceValue("")
        XCTAssertNil(try XCTUnwrap(a.read)())
        a.focus?(false)
        try await s.settle()
        try s.expectValue("")
    }

    @MainActor func testConstantBindingKeepsDraftAcrossRefreshAndRestoresOriginalOnReturn() async throws {
        let a = FieldActions()
        let s = try await ScreenWindow(CodeEntry(mode: .constant, actions: a), width: 220, height: 100, keyboard: true)
        defer { s.close() }
        a.focus?(true)
        try await s.settle()
        try await s.replaceValue("101")
        a.change?(42)
        try await s.settle()
        try s.expectValue("101")
        try await s.pressReturn()
        try s.expectValue("12")
    }

    @MainActor func testNumberUsesItsFormatStyleOnReturnAndOnExternalChange() async throws {
        let a = FieldActions()
        let s = try await ScreenWindow(CodeEntry(mode: .number, actions: a), width: 220, height: 100, keyboard: true)
        defer { s.close() }
        a.focus?(true)
        try await s.settle()
        try await s.replaceValue("001234")
        try s.expectValue("001234")
        XCTAssertEqual(a.read?(), 1234)
        try await s.pressReturn()
        try s.expectValue("1,234")
        try await s.replaceValue("0009")
        a.change?(4256)
        try await s.settle()
        try s.expectValue("4,256")
    }
}
