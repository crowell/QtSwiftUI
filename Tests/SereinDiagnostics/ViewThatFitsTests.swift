import SwiftUI
import XCTest

@MainActor @Observable private final class FittingModel {
    var width: CGFloat = 90
    var height: CGFloat = 90
    var axes: Axis.Set = .horizontal
    var appeared: [Int] = []
    var disappeared: [Int] = []
    var taps: [Int] = []
    var preference = -1
}

private struct ChoiceKey: PreferenceKey {
    static let defaultValue = -1
    static func reduce(value: inout Int, nextValue: () -> Int) { value = max(value, nextValue()) }
}

private struct FittingExample: View {
    let model: FittingModel
    var body: some View {
        ViewThatFits(in: model.axes) {
            ForEach(0..<3, id: \.self) { i in
                Button { model.taps.append(i) } label: {
                    Color.blue.frame(width: [120, 85, 50][i], height: [25, 70, 45][i])
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
                .onAppear { model.appeared.append(i) }
                .onDisappear { model.disappeared.append(i) }
                .preference(key: ChoiceKey.self, value: i)
            }
        }
        .onPreferenceChange(ChoiceKey.self) { model.preference = $0 }
        .frame(width: model.width, height: model.height)
    }
}

private struct ChoiceGuideProbe: Layout {
    let record: ([CGFloat?]) -> Void
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize { CGSize(width: 180, height: 50) }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        record([60, 120].flatMap { (width: CGFloat) -> [CGFloat?] in
            let d = subviews[0].dimensions(in: .init(width: width, height: 50))
            return [d.width, d.height, d[explicit: .leading], d[explicit: .firstTextBaseline]]
        })
        subviews[0].place(at: bounds.origin, proposal: .init(bounds.size))
    }
}

final class ViewThatFitsTests: XCTestCase {
    @MainActor func testSizeAndExplicitGuidesFollowTheSelectedCandidate() async throws {
        var dimensions: [CGFloat?] = []
        let view = ChoiceGuideProbe(record: { dimensions = $0 }) {
            ViewThatFits(in: .horizontal) {
                Color.red.frame(width: 120, height: 30).alignmentGuide(.firstTextBaseline) { _ in 3 }.alignmentGuide(.leading) { _ in 5 }
                Color.blue.frame(width: 40, height: 45).alignmentGuide(.firstTextBaseline) { _ in 9 }.alignmentGuide(.leading) { _ in 12 }
            }
        }
        let window = try await ScreenWindow(view, width: 180, height: 50)
        defer { window.close() }
        XCTAssertEqual(dimensions, [40, 45, 12, 9, 120, 30, 5, 3])
    }

    @MainActor func testChoiceIdentityAndInteractionAcrossWidthChanges() async throws {
        let m = FittingModel()
        let w = try await ScreenWindow(FittingExample(model: m), width: 200, height: 120)
        defer { w.close() }
        for (width, expected) in [(90, 1), (120, 0), (20, 2), (85, 1)] {
            m.width = CGFloat(width)
            try await w.settle()
            try await w.click(100, 60)
            XCTAssertEqual(m.taps.last, expected)
            XCTAssertEqual(m.preference, expected)
        }
        XCTAssertEqual(m.appeared, [1, 0, 2, 1])
        XCTAssertEqual(m.disappeared, [1, 0, 2])
        #if os(Linux)
        try await w.pressReturn()
        XCTAssertEqual(m.taps, [1, 0, 2, 1, 1])
        #endif
    }

    @MainActor func testChecksOnlyRequestedAxesAndFallsBackToLast() async throws {
        let m = FittingModel()
        m.width = 90
        m.height = 40
        let w = try await ScreenWindow(FittingExample(model: m), width: 200, height: 120)
        defer { w.close() }
        let cases: [(Axis.Set, Int)] = [(.vertical, 0), (.horizontal, 1), ([.vertical, .horizontal], 2), ([], 0)]
        for (axes, expected) in cases {
            m.axes = axes
            try await w.settle()
            try await w.click(100, 60)
            XCTAssertEqual(m.taps.last, expected)
        }
    }
}
