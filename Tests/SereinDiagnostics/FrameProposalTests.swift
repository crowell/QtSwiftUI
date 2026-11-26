import SwiftUI
import XCTest

private struct IntrinsicChild: Layout {
    let ideal: CGSize
    let placed: (ProposedViewSize) -> Void
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions(by: ideal)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        placed(proposal)
        subviews[0].place(at: bounds.origin, proposal: ProposedViewSize(bounds.size))
    }
}

final class FrameProposalTests: XCTestCase {
    @MainActor func testUnspecifiedDimensionsAreReproposedOnlyOutsideLimits() async throws {
        for (ideal, expected) in [(CGSize(width: 40, height: 8), ProposedViewSize(width: nil, height: 80)),
                                  (CGSize(width: 120, height: 250), ProposedViewSize(width: 60, height: 200)),
                                  (CGSize(width: 30, height: 100), .unspecified)] {
            var placements: [ProposedViewSize] = []
            let view = IntrinsicChild(ideal: ideal, placed: { placements.append($0) }) { Color.black }
                .frame(minWidth: 20, maxWidth: 60, minHeight: 80, maxHeight: 200).fixedSize()
            let window = try await ScreenWindow(view, width: 180, height: 260)
            XCTAssertEqual(placements.last, expected)
            window.close()
        }
    }
}
