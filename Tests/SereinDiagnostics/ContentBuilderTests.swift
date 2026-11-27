import SwiftUI
import XCTest

private func build<Content>(@ContentBuilder _ content: () -> Content) -> Content { content() }

@MainActor @Observable private final class RowState {
    var showMiddle = false
    var lastCount = 0
}
private struct CounterRow: View {
    @State var count = 0
    let state: RowState
    var body: some View {
        Color.blue.frame(height: 20).onTapGesture {
            count += 1
            state.lastCount = count
        }
    }
}

final class ContentBuilderTests: XCTestCase {
    @MainActor func testConditionalSiblingPreservesStateInLazyTupleRows() async throws {
        let state = RowState()
        struct Rows: View {
            let state: RowState
            var body: some View {
                LazyVStack(spacing: 0) {
                    Color.red.frame(height: 20)
                    if state.showMiddle { Color.green.frame(height: 20) }
                    CounterRow(state: state)
                }.frame(maxHeight: .infinity, alignment: .top)
            }
        }
        let s = try await ScreenWindow(Rows(state: state), width: 100, height: 85)
        defer { s.close() }
        try await s.click(50, 30)
        XCTAssertEqual(state.lastCount, 1)
        state.showMiddle = true
        try await s.settle()
        try await s.click(50, 50)
        XCTAssertEqual(state.lastCount, 2)
        state.showMiddle = false
        try await s.settle()
        try await s.click(50, 30)
        XCTAssertEqual(state.lastCount, 3)
    }

    @MainActor func testDataAndViewsShareTheDesktopBuilder() async throws {
        let _: EmptyContent = build {}
        let single = build { 17 }
        XCTAssertEqual(single, 17)
        let mixed: TupleContent<Int, String> = build {
            1
            "row"
        }
        func acceptsSendable<T: Sendable>(_ value: T) {}
        acceptsSendable(mixed)
        XCTAssertEqual(mixed.content.0, 1)
        XCTAssertEqual(mixed.content.1, "row")
        func optional(_ flag: Bool) -> Int? { build { if flag { 9 } } }
        XCTAssertEqual(optional(true), 9)
        XCTAssertNil(optional(false))
        func branches(_ flag: Bool) -> _ConditionalContent<Int, String> { build { if flag { 9 } else { "row" } } }
        _ = branches(false)
        let inferred = build {
            Color.red
            Color.blue
        }
        XCTAssertTrue(type(of: inferred) == TupleContent<Color, Color>.self)
        let legacy: TupleView<(Color, Color)> = build {
            Color.red
            Color.blue
        }
        for view in [AnyView(inferred), AnyView(legacy)] {
            let s = try await ScreenWindow(HStack(spacing: 0) { view }, width: 100, height: 40)
            XCTAssertGreaterThan((s.pixel(25, 20) >> 16) & 255, s.pixel(25, 20) & 255)
            XCTAssertGreaterThan(s.pixel(75, 20) & 255, (s.pixel(75, 20) >> 16) & 255)
            s.close()
        }
    }
}
