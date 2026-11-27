import SwiftUI
import XCTest

@MainActor private final class FocusLog {
    var values: [String: Bool] = [:]
    var changes: [Bool] = []
    var move: ((Int) -> Void)?
    var requestBoolean: (() -> Void)?
    var booleanValue: (() -> Bool)?
}

private struct FocusReader: View {
    @Environment(\.isFocused) var focus
    let name: String
    let log: FocusLog
    var body: some View {
        Color.blue.frame(width: 22, height: 22)
            .onAppear { log.values[name] = focus }
            .onChange(of: focus) { _, new in log.values[name] = new }
    }
}

private func booleanTarget<V: View>(_ view: V, binding: FocusState<Bool>.Binding) -> some View {
    view.focusable(interactions: .edit).focusEffectDisabled().focused(binding, equals: true)
}

private struct FocusTree: View {
    @FocusState private var current: Int?
    @FocusState private var boolean: Bool
    let log: FocusLog
    var body: some View {
        VStack {
            FocusReader(name: "outside", log: log)
            HStack {
                FocusReader(name: "outer", log: log)
                FocusReader(name: "declaration", log: log).focusable(interactions: .edit).focused($current, equals: 5)
                VStack { FocusReader(name: "inner", log: log) }.focusable(interactions: .edit).focused($current, equals: 2)
            }
            .focusable(interactions: .edit).focused($current, equals: 1)
            VStack { FocusReader(name: "other", log: log) }
                .focusable(true, onFocusChange: { log.changes.append($0) }).focused($current, equals: 3)
            VStack { FocusReader(name: "last", log: log) }.focusable(interactions: .edit).focused($current, equals: 4)
            booleanTarget(VStack { FocusReader(name: "boolean", log: log) }, binding: $boolean)
        }.onAppear {
            log.move = { current = $0 }
            log.requestBoolean = { boolean = true }
            log.booleanValue = { boolean }
        }
    }
}

final class FocusEnvironmentTests: XCTestCase {
    @MainActor func testNearestFocusableAncestorAndChangeCallback() async throws {
        let log = FocusLog()
        let window = try await ScreenWindow(FocusTree(log: log), width: 200, height: 200, keyboard: true)
        defer { window.close() }
        let move = try XCTUnwrap(log.move)
        for (target, active) in [(1, "outer"), (2, "inner"), (3, "other"), (4, "last"), (1, "outer")] {
            move(target)
            try await window.settle()
            try await window.settle()
            // A view that declares its own focus target reads the enclosing target.
            XCTAssertEqual(log.values["declaration"], target == 1)
            let focused = log.values.filter { $0.key != "declaration" && $0.value }.map(\.key)
            XCTAssertEqual(focused, [active], "Focus target \(target)")
            XCTAssertEqual(log.values["outside"], false)
        }
        XCTAssertEqual(log.changes, [true, false])
        log.requestBoolean?()
        try await window.settle()
        try await window.settle()
        XCTAssertEqual(log.values["boolean"], true)
        move(2)
        try await window.settle()
        try await window.settle()
        XCTAssertEqual(log.booleanValue?(), false)
        XCTAssertEqual(log.values["inner"], true)
    }
}
