import SwiftUI
import XCTest
#if os(Linux)
@testable import SwiftUI
import QtBridge
#endif

@MainActor @Observable private final class FormModel {
    var blocks = false
    var triggers: SubmitTriggers = [.text, .search]
    var label: SubmitLabel = .search
    var events: [String] = []
}

private struct SubmitForm: View {
    let model: FormModel
    var body: some View {
        VStack(spacing: 0) {
            TextField("Query", text: .constant(""))
                .textFieldStyle(.plain)
                .submitLabel(model.label)
                .onSubmit { model.events.append("field") }
                .submitScope(model.blocks)
                .onSubmit(of: model.triggers) { model.events.append("group") }
                .frame(height: 50)
            SecureField("Code", text: .constant(""))
                .onSubmit { model.events.append("secure") }
                .frame(height: 50)
            TextField("Notes", text: .constant(""), axis: .vertical)
                .submitLabel(.return)
                .frame(height: 50)
        }
        .submitLabel(.done)
        .onSubmit { model.events.append("form") }
    }
}

final class SubmitTests: XCTestCase {
    func testTriggerRawValues() {
        let text: Int = SubmitTriggers.text.rawValue
        let search: Int = SubmitTriggers.search.rawValue
        XCTAssertEqual(text, 1)
        XCTAssertEqual(search, 4)
        XCTAssertFalse(SubmitTriggers(rawValue: 2).contains(.search))
        XCTAssertEqual(SubmitTriggers(rawValue: -1).intersection([.text, .search]), [.text, .search])
    }

    @MainActor func testReturnRoutesOnlyThroughMatchingUnblockedHandlers() async throws {
        let model = FormModel()
        let window = try await ScreenWindow(SubmitForm(model: model), width: 240, height: 150, keyboard: true)
        defer { window.close() }
        func check(_ y: Int, _ expected: [String], line: UInt = #line) async throws {
            model.events.removeAll()
            try await window.settle()
            try await window.click(90, y)
            try await window.pressReturn()
            XCTAssertEqual(model.events, expected, line: line)
        }
        try await check(25, ["form", "group", "field"])
        model.blocks = true
        try await check(25, ["field"])
        model.blocks = false
        model.triggers = .search
        try await check(25, ["field"])
        try await check(75, ["form", "secure"])
        try await check(125, ["form"])
    }

    #if os(Linux)
    @MainActor func testEditorInputMethodsInheritOrOverrideTheirLabel() async throws {
        let editors = VStack(spacing: 0) {
            TextEditor(text: .constant("plain")).frame(height: 60)
            TextEditor(text: .constant(AttributedString("rich"))).submitLabel(.next).frame(height: 60)
        }.submitLabel(.go)
        let window = try await ScreenWindow(editors, width: 220, height: 120, keyboard: true)
        defer { window.close() }
        try await window.click(80, 30)
        XCTAssertEqual(qs_focused_enter_key(window.host.window), 3)
        try await window.click(80, 90)
        XCTAssertEqual(qs_focused_enter_key(window.host.window), 6)
    }

    @MainActor func testFocusedInputMethodReceivesTheCurrentSubmitLabel() async throws {
        let model = FormModel()
        let window = try await ScreenWindow(SubmitForm(model: model), width: 240, height: 150, keyboard: true)
        defer { window.close() }
        try await window.click(90, 25)
        let labels: [(SubmitLabel, Int32)] = [(.return, 1), (.done, 2), (.go, 3), (.send, 4),
                                              (.join, 3), (.route, 3), (.search, 5), (.next, 6), (.continue, 6)]
        for (label, key) in labels {
            model.label = label
            try await window.settle()
            XCTAssertEqual(qs_focused_enter_key(window.host.window), key)
        }
        try await window.click(90, 75)
        XCTAssertEqual(qs_focused_enter_key(window.host.window), 2)
        try await window.click(90, 125)
        XCTAssertEqual(qs_focused_enter_key(window.host.window), 1)
    }
    #endif
}
