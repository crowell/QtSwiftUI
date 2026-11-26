import SwiftUI
import XCTest

private enum ThirdOfWidth: AlignmentID {
    static func defaultValue(in context: ViewDimensions) -> CGFloat { context.width / 3 }
}

private let column = HorizontalAlignment(ThirdOfWidth.self)

private struct GuideProbe: Layout {
    let record: ([[CGFloat?]]) -> Void
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        CGSize(width: 320, height: 100)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        record(subviews.map {
            let d = $0.dimensions(in: .unspecified)
            return [d.width, d.height, d[explicit: .leading], d[explicit: .trailing], d[explicit: .top], d[explicit: column]]
        })
        for (i, view) in subviews.enumerated() { view.place(at: CGPoint(x: 32 * i, y: 0), proposal: .unspecified) }
    }
}

final class AlignmentGuideTests: XCTestCase {
    @MainActor func testGuideCombinationAndPropagation() async throws {
        XCTAssertNil(HorizontalAlignment.leading.combineExplicit([2, nil, 8]))
        XCTAssertEqual(VerticalAlignment.firstTextBaseline.combineExplicit([2, nil, 8]), 2)
        XCTAssertEqual(VerticalAlignment.lastTextBaseline.combineExplicit([2, nil, 8]), 8)
        XCTAssertEqual(column.combineExplicit([2, nil, 8]), 5)
        var readings: [[CGFloat?]] = []
        let a = Color.red.frame(width: 20, height: 12)
            .alignmentGuide(.leading) { _ in 6 }.alignmentGuide(.trailing) { _ in 10 }
            .alignmentGuide(.top) { _ in 4 }.alignmentGuide(column) { _ in 6 }
        let screen = GuideProbe(record: { readings = $0 }) {
            a
            a.padding(.leading, 3).padding(.top, 2)
            a.frame(width: 50, height: 36, alignment: .topTrailing)
            HStack(spacing: 8) { a; a }
            VStack(alignment: .leading, spacing: 8) { a; Color.red.frame(width: 22, height: 10) }
            ZStack(alignment: .topTrailing) { a; Color.red.frame(width: 22, height: 18) }
            VStack(alignment: column, spacing: 8) { a; Color.red.frame(width: 30, height: 10) }
            a.overlay(alignment: .topTrailing) { a.alignmentGuide(column) { _ in 17 } }
            a.alignmentGuide(.leading) { $0[.leading] + 1 }
        }
        let window = try await ScreenWindow(screen, width: 320, height: 100)
        defer { window.close() }
        XCTAssertEqual(readings, [
            [20, 12, 6, 10, 4, 6], [23, 14, 9, 13, 6, 9], [50, 36, 46, 50, 0, 46],
            [48, 12, nil, nil, nil, 20], [28, 30, nil, nil, nil, 6], [32, 22, nil, nil, nil, 18], [30, 30, nil, nil, nil, 10],
            [20, 12, 6, 10, 4, 6], [20, 12, 7, 10, 4, 6]
        ])
    }

    @MainActor func testTrailingBadgeMirrorsInRightToLeftLayouts() async throws {
        for direction in [LayoutDirection.leftToRight, .rightToLeft] {
            var badge = CGRect.zero, icon = CGRect.zero
            let view = Color.blue.frame(width: 32, height: 28)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { icon = $0 }
                .overlay(alignment: .topTrailing) {
                    Color.red.frame(width: 16, height: 16)
                        .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { badge = $0 }
                        .alignmentGuide(.top) { _ in 4 }.alignmentGuide(.trailing) { $0.width - 6 }
                }
                .environment(\.layoutDirection, direction)
            let window = try await ScreenWindow(view, width: 80, height: 80)
            try await window.settle()
            XCTAssertEqual(badge.minY, icon.minY - 4)
            XCTAssertEqual(badge.minX, direction == .leftToRight ? icon.maxX - 10 : icon.minX - 6)
            window.close()
        }
    }
}
