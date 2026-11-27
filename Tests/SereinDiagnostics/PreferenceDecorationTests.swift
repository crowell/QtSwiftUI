import SwiftUI
import XCTest

private enum LayerNames: PreferenceKey {
    static let defaultValue: [String] = []
    static func reduce(value: inout [String], nextValue: () -> [String]) {
        value += nextValue()
    }
}

private enum BranchNames: PreferenceKey {
    static let defaultValue: [String] = []
    static func reduce(value: inout [String], nextValue: () -> [String]) { value += nextValue() }
}

private struct DecorationProbe: View {
    let alignment: Alignment?
    let observed: ([String]) -> Void
    let branches: ([String]) -> Void

    @ViewBuilder var body: some View {
        let base = Color.clear.frame(width: 60, height: 40)
            .preference(key: LayerNames.self, value: ["base"])
            .preference(key: BranchNames.self, value: ["base"])
        Group {
            if let alignment {
                base.overlayPreferenceValue(LayerNames.self, alignment: alignment, foreground)
                    .backgroundPreferenceValue(LayerNames.self, alignment: alignment, background)
            } else {
                let front = centered(base.overlayPreferenceValue(_:_:), foreground)
                centered(front.backgroundPreferenceValue(_:_:), background)
            }
        }
        .onPreferenceChange(LayerNames.self, perform: observed)
        .onPreferenceChange(BranchNames.self, perform: branches)
    }

    // Retain the overload with two parameters when taking a method reference.
    nonisolated private func centered<V: View, D: View>(
        _ decorate: (LayerNames.Type, @escaping ([String]) -> D) -> V,
        _ content: @escaping ([String]) -> D
    ) -> V {
        decorate(LayerNames.self, content)
    }

    private func foreground(_ names: [String]) -> some View {
        (names == ["base"] ? Color.black : Color.white).frame(width: 8, height: 8)
            .preference(key: LayerNames.self, value: ["front"])
            .preference(key: BranchNames.self, value: ["front"])
    }

    private func background(_ names: [String]) -> some View {
        Color(white: names == (alignment == nil ? ["base"] : ["base", "front"]) ? 0.5 : 1).frame(width: 20, height: 20)
            .preference(key: LayerNames.self, value: ["back"])
            .preference(key: BranchNames.self, value: ["back"])
    }
}

final class PreferenceDecorationTests: XCTestCase {
    @MainActor func testDecoratingAGroupInsideAHorizontalStack() async throws {
        var values: [String] = []
        let root = HStack(spacing: 0) {
            Group {
                Color.white.frame(width: 30, height: 20).preference(key: LayerNames.self, value: ["left"])
                Color.white.frame(width: 50, height: 20).preference(key: LayerNames.self, value: ["right"])
            }
            .overlayPreferenceValue(LayerNames.self, alignment: .trailing) { names in
                Color.black.frame(width: 4, height: 10)
                    .preference(key: BranchNames.self, value: [names.joined(separator: "+")])
            }
        }
        .onPreferenceChange(BranchNames.self) { values = $0 }
        .background(Color.white)
        let window = try await ScreenWindow(root, width: 80, height: 40)
        defer { window.close() }
        try await window.settle()
        XCTAssertEqual(values, ["left", "right"])
        XCTAssertEqual(window.pixel(28, 20), 0)
        XCTAssertEqual(window.pixel(78, 20), 0)
    }

    @MainActor func testDecorationsReadOnlyTheirBaseAndPublishBothBranches() async throws {
        for alignment in [nil, Alignment.topLeading] {
            var observed: [String] = []
            var branches: [String] = []
            let root = DecorationProbe(alignment: alignment, observed: { observed = $0 }, branches: { branches = $0 })
                .background(Color.white)
            let window = try await ScreenWindow(root, width: 80, height: 60)
            defer { window.close() }
            try await window.settle()
            XCTAssertEqual(observed, alignment == nil ? ["base"] : ["back", "base", "front"])
            XCTAssertEqual(branches, ["back", "base", "front"])
            let corner = alignment == nil ? CGPoint(x: 30, y: 20) : CGPoint(x: 10, y: 10)
            let x = Int(corner.x), y = Int(corner.y)
            let front = alignment == nil ? 10 : 4
            XCTAssertEqual(window.pixel(x + front, y + front), 0)
            let gray = window.pixel(x + 16, y + 16) & 255
            XCTAssertGreaterThan(gray, 70)
            XCTAssertLessThan(gray, 220)
            XCTAssertEqual(window.pixel(68, 48), 0xffffff)
        }
    }
}
