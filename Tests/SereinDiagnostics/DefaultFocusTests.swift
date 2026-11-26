import SwiftUI
import XCTest

private func region<Content: View>(_ view: Content, binding: FocusState<Int?>.Binding) -> some View {
    view.defaultFocus(binding, 2, priority: .automatic)
}

private struct DefaultFields: View {
    @FocusState private var value: Int?
    let record: (Int?) -> Void
    let install: (@escaping (Int) -> Void) -> Void

    var body: some View {
        VStack {
            TextField("Outside", text: .constant("")).focused($value, equals: 0)
            region(VStack {
                TextField("First", text: .constant("")).focused($value, equals: 1)
                TextField("Default", text: .constant("")).focused($value, equals: 2)
            }, binding: $value)
        }
        .onChange(of: value, initial: true) { _, latest in record(latest) }
        .onAppear { install { value = $0 } }
    }
}

final class DefaultFocusTests: XCTestCase {
    @MainActor func testProgrammaticEntryUsesThePreferredField() async throws {
        var value: Int?
        var select: ((Int) -> Void)?
        let window = try await ScreenWindow(DefaultFields(record: { value = $0 }, install: { select = $0 }),
                                            width: 200, height: 140, keyboard: true)
        defer { window.close() }
        try XCTUnwrap(select)(0)
        for _ in 0..<20 where value != 0 { try await window.settle() }
        XCTAssertEqual(value, 0)
        try XCTUnwrap(select)(1)
        for _ in 0..<6 { try await window.settle() }
        XCTAssertEqual(value, 2)
    }
}
