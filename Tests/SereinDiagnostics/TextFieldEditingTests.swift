import SwiftUI
import XCTest

@MainActor private final class FieldEvents {
    var log: [String] = []
    var focus: ((Int) -> Void)?
}

private struct EditingFields: View {
    @State var text = ""
    @FocusState var focus: Int?
    let events: FieldEvents

    var body: some View {
        VStack {
            Color.blue.frame(height: 12).focusable(interactions: .edit).focused($focus, equals: 1)
            TextField("Name", text: $text, onEditingChanged: { events.log.append($0 ? "begin" : "end") },
                      onCommit: { events.log.append("commit") })
                .focused($focus, equals: 2).onSubmit { events.log.append("submit") }
            SecureField(String("Secret").dropLast(), text: $text, onCommit: { events.log.append("secure commit") })
                .focused($focus, equals: 3).onSubmit { events.log.append("secure submit") }
        }.onAppear { events.focus = { focus = $0 } }
    }
}

final class TextFieldEditingTests: XCTestCase {
    @MainActor func testFocusTypingReturnAndCommitOrder() async throws {
        let events = FieldEvents()
        let screen = try await ScreenWindow(EditingFields(events: events), width: 200, height: 110, keyboard: true)
        defer { screen.close() }
        let focus = try XCTUnwrap(events.focus)
        func expect(_ log: [String], line: UInt = #line) {
            XCTAssertEqual(events.log, log, line: line)
            events.log.removeAll()
        }
        focus(1)
        try await screen.settle()
        events.log.removeAll()
        focus(2)
        try await screen.settle()
        expect(["begin"])
        focus(1)
        try await screen.settle()
        expect(["end", "commit"])
        focus(2)
        try await screen.settle()
        expect(["begin"])
        try await screen.type("a")
        try await screen.type("b")
        expect(["begin"])
        for _ in 0..<2 {
            try await screen.pressReturn()
            expect(["end", "commit", "submit"])
        }
        try await screen.type("c")
        expect(["begin"])
        focus(3)
        try await screen.settle()
        expect(["end", "commit"])
        try await screen.pressReturn()
        expect(["secure commit", "secure submit"])
        focus(1)
        try await screen.settle()
        expect(["secure commit"])
    }
}
