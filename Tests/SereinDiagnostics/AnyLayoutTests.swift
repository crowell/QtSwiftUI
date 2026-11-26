import SwiftUI
import XCTest

private struct CachedRow: Layout {
    struct Cache { var count: Int }
    func makeCache(subviews: Subviews) -> Cache { .init(count: subviews.count) }
    func updateCache(_ cache: inout Cache, subviews: Subviews) { cache.count = subviews.count }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        CGSize(width: 40 * cache.count, height: 24)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        for (n, subview) in subviews.enumerated() {
            subview.place(at: CGPoint(x: bounds.minX + CGFloat(n * 40), y: bounds.minY), proposal: .unspecified)
        }
    }
}

private struct CounterLayout: Layout {
    func makeCache(subviews: Subviews) -> Int { 3 }
    func updateCache(_ cache: inout Int, subviews: Subviews) { cache += 10 }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Int) -> CGSize {
        cache += 1
        return CGSize(width: cache, height: 10)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Int) {}
}

private struct CopyCacheProbe: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let layout = AnyLayout(CounterLayout())
        var a = layout.makeCache(subviews: subviews), b = a
        layout.updateCache(&a, subviews: subviews)
        XCTAssertEqual(layout.sizeThatFits(proposal: proposal, subviews: subviews, cache: &a).width, 14)
        XCTAssertEqual(layout.sizeThatFits(proposal: proposal, subviews: subviews, cache: &b).width, 4)
        return CGSize(width: 90, height: 40)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for subview in subviews { subview.place(at: bounds.origin, proposal: proposal) }
    }
}

@MainActor @Observable private final class LayoutSwitch {
    var mode = 0
    var taps: [Int] = []
    var frames: [Int: CGRect] = [:]
}

private struct CountButton: View {
    let record: (Int) -> Void
    @State private var count = 0
    var body: some View {
        Button { count += 1; record(count) } label: { Color.blue.frame(width: 24, height: 24) }
            .buttonStyle(.plain)
    }
}

private struct SwitchingRow: View {
    let model: LayoutSwitch
    var body: some View {
        let layout = model.mode == 0 ? AnyLayout(HStackLayout(spacing: 6)) :
            model.mode == 1 ? AnyLayout(VStackLayout(spacing: 6)) : AnyLayout(CachedRow())
        layout {
            CountButton { model.taps.append($0) }
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("box")) } action: { model.frames[0] = $0 }
            Color.red.frame(width: 24, height: 24)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("box")) } action: { model.frames[1] = $0 }
        }.frame(width: 120, height: 120, alignment: .topLeading).coordinateSpace(name: "box")
    }
}

final class AnyLayoutTests: XCTestCase {
    @MainActor func testCopiesOfErasedCacheUpdateIndependently() async throws {
        let window = try await ScreenWindow(CopyCacheProbe { Color.blue }, width: 90, height: 40)
        window.close()
    }

    @MainActor func testTypeErasedLayoutKeepsChildStateAcrossAxesAndCustomCache() async throws {
        XCTAssertNil(HStackLayout.layoutProperties.stackOrientation)
        XCTAssertNil(VStackLayout.layoutProperties.stackOrientation)
        let model = LayoutSwitch()
        let window = try await ScreenWindow(SwitchingRow(model: model), width: 120, height: 120)
        defer { window.close() }
        for (mode, offset) in [(0, CGPoint(x: 30, y: 0)), (1, CGPoint(x: 0, y: 30)), (2, CGPoint(x: 40, y: 0)), (0, CGPoint(x: 30, y: 0))] {
            model.mode = mode
            try await window.settle()
            XCTAssertEqual(model.frames[0]?.origin, .zero)
            XCTAssertEqual(model.frames[1]?.origin, offset)
            try await window.click(12, 12)
        }
        XCTAssertEqual(model.taps, [1, 2, 3, 4])
    }
}
