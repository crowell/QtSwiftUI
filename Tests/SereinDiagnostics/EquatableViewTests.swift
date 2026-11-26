import SwiftUI
import XCTest

@MainActor private final class RenderCounter { var bodies = 0 }
@MainActor @Observable private final class RowModel {
    var value = 1
    var parent = 0
    var revision = 0
}

private struct CountingRow: View, Equatable {
    let number: Int
    let counter: RenderCounter
    let model: RowModel

    nonisolated static func == (left: Self, right: Self) -> Bool {
        left.number == right.number && left.model === right.model && left.counter === right.counter
    }
    var body: some View {
        counter.bodies += 1
        return Text("\(number) \(model.value)")
    }
}

final class EquatableViewTests: XCTestCase {
    @MainActor func testEqualParentUpdatesReuseBodyAndObservedChangesInvalidateIt() async throws {
        struct Parent: View {
            let model: RowModel
            let counter: RenderCounter
            var body: some View {
                VStack {
                    Text("\(model.parent)")
                    CountingRow(number: model.revision, counter: counter, model: model).equatable()
                }
            }
        }
        let model = RowModel(), counter = RenderCounter()
        let window = try await ScreenWindow(Parent(model: model, counter: counter), width: 190, height: 70)
        defer { window.close() }
        let initial = counter.bodies
        XCTAssertGreaterThan(initial, 0)
        model.parent += 1
        try await window.settle()
        XCTAssertEqual(counter.bodies, initial)
        model.value += 1
        try await window.settle()
        XCTAssertGreaterThan(counter.bodies, initial)
        let observed = counter.bodies
        model.revision += 1
        try await window.settle()
        XCTAssertGreaterThan(counter.bodies, observed)
    }
}
