import SwiftUI
import XCTest

@MainActor @Observable private final class SearchModel {
    var text = "before"
    var selection: TextSelection?
}

private enum SearchControl { case field, verticalField }

private struct SnapshotField: View {
    let control: SearchControl
    let model: SearchModel
    var body: some View {
        @Bindable var bound = model
        // Serein’s left-pane helper supplies the latest value with each render.
        let current = model.text
        let text = Binding(get: { current }, set: { model.text = $0 })
        switch control {
        case .field: TextField("Search", text: text, selection: $bound.selection).textFieldStyle(.plain)
        case .verticalField: TextField("Search", text: text, selection: $bound.selection, axis: .vertical).textFieldStyle(.plain)
        }
    }
}

final class FieldCursorTests: XCTestCase {
    @MainActor func testFieldTypingAdvancesTheSelection() async throws { try await check(.field) }
    @MainActor func testVerticalFieldTypingAdvancesTheSelection() async throws { try await check(.verticalField) }

    @MainActor private func check(_ control: SearchControl) async throws {
        let model = SearchModel()
        let window = try await ScreenWindow(SnapshotField(control: control, model: model), width: 220, height: 50, keyboard: true)
        defer { window.close() }
        try await window.click(75, 25)
        model.selection = .init(range: model.text.startIndex..<model.text.endIndex)
        try await window.settle()
        var expected = ""
        for input in ["H", "a", "🚢", "r", "b", "o", "r"] {
            try await window.type(input)
            expected += input
            XCTAssertEqual(model.text, expected)
            guard case .selection(let range) = model.selection?.indices else { return XCTFail("Missing caret") }
            XCTAssertTrue(range.isEmpty)
            XCTAssertEqual(range.lowerBound.utf16Offset(in: model.text), expected.utf16.count)
        }
    }
}
