import SwiftUI
import XCTest
#if os(Linux)
@testable import SwiftUI
import QtBridge
#endif

@MainActor @Observable private final class FieldModel {
    var text = ""
    var height: CGFloat = 0
    var submitted = 0
}

private struct CounterButton: View {
    @State private var count = 0
    var record: (Int) -> Void
    var body: some View {
        Button("Increment") {
            count += 1
            record(count)
        }.frame(width: 100, height: 48)
    }
}

final class FieldCompatibilityTests: XCTestCase {
    @MainActor func testReusedViewHasIndependentStateInEachPosition() async throws {
        var counts: [Int] = []
        let counter = CounterButton { counts.append($0) }
        let window = try await ScreenWindow(VStack(spacing: 0) { counter; counter }, width: 120, height: 96)
        defer { window.close() }
        try await window.click(60, 24)
        try await window.click(60, 72)
        try await window.click(60, 24)
        XCTAssertEqual(counts, [1, 1, 2])
    }

    @MainActor func testVerticalFieldWrapsReservesAndCapsHeight() async throws {
        let model = FieldModel()
        @Bindable var bound = model
        let field = TextField("Name", text: $bound.text, prompt: Text("Enter name"), axis: .vertical)
            .textFieldStyle(.plain).lineLimit(2...3)
            .fixedSize(horizontal: false, vertical: true)
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { model.height = $0 }
            .frame(width: 100)
        let window = try await ScreenWindow(field, width: 150, height: 120)
        defer { window.close() }
        try await window.settle()
        let initial = model.height
        XCTAssertGreaterThan(initial, 15)
        model.text = "one\ntwo"
        try await window.settle()
        XCTAssertEqual(model.height, initial, accuracy: 1)
        model.text = "one\ntwo\n"
        try await window.settle()
        let capped = model.height
        XCTAssertGreaterThan(capped, initial + 5)
        model.text = String(repeating: "some words ", count: 40)
        try await window.settle()
        XCTAssertEqual(model.height, capped, accuracy: 1)
        model.text = "short"
        try await window.settle()
        XCTAssertEqual(model.height, initial, accuracy: 1)
    }

    @MainActor func testVerticalFieldReturnAndOptionReturn() async throws {
        let model = FieldModel()
        @Bindable var bound = model
        let field = TextField("Note", text: $bound.text, axis: .vertical).textFieldStyle(.plain)
            .onSubmit { model.submitted += 1 }.frame(width: 130)
        let window = try await ScreenWindow(field, width: 160, height: 100, keyboard: true)
        defer { window.close() }
        try await window.click(60, 50)
        try await window.type("First")
        try await window.pressReturn(option: true)
        try await window.type("Second")
        XCTAssertEqual(model.text, "First\nSecond")
        try await window.pressReturn()
        XCTAssertEqual(model.submitted, 1)
        XCTAssertEqual(model.text, "First\nSecond")
    }

    @MainActor func testAnchoredScalePreservesLayout() async throws {
        let view = Color.red.frame(width: 40, height: 40).scaleEffect(x: 0.5, y: 1, anchor: .leading)
            .frame(width: 100, height: 100).background(Color.white)
        let window = try await ScreenWindow(view, width: 100, height: 100)
        defer { window.close() }
        XCTAssertNotEqual(window.pixel(35, 50), window.pixel(5, 50))
        XCTAssertEqual(window.pixel(55, 50), window.pixel(5, 50))
    }

    #if os(Linux)
    @MainActor func testAccessibilityActionsShareAnElement() async throws {
        var events: [String] = []
        let view = Text("Find").accessibilityElement().accessibilityLabel("Search")
            .accessibilityAddTraits(.isSearchField).accessibilityHint("Edit your search")
            .accessibilityAction { events.append("open") }
            .accessibilityAction(named: Text("Clear")) { events.append("clear") }
        let window = try await ScreenWindow(view, width: 100, height: 100)
        defer { window.close() }
        XCTAssertEqual(qs_accessible_element(window.host.window, "Search", 0, "Press"), 1)
        XCTAssertEqual(qs_accessible_element(window.host.window, "Search", 0, "Clear"), 1)
        XCTAssertEqual(events, ["open", "clear"])
    }
    #endif
}
