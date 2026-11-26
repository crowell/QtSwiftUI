import XCTest
import SwiftUI

final class CornerTests: XCTestCase {
    func testUnequalCornersAndCrowdedEdges() {
        let rect = CGRect(x: 0, y: 0, width: 60, height: 40)
        let radii = RectangleCornerRadii(topLeading: 80, bottomLeading: 40, bottomTrailing: 5, topTrailing: 30)
        // Boundaries through the SDK path where the upper and left corner pairs compete for an edge.
        let circular = [[14,37],[10,42],[6,47],[3,51],[0,57],[6,59],[11,58],[14,57]]
        let continuous = [[14,36],[10,42],[6,48],[3,52],[0,57],[5,59],[11,58],[14,57]]
        for (style, expected) in [(RoundedCornerStyle.circular, circular), (.continuous, continuous)] {
            let shape = UnevenRoundedRectangle(cornerRadii: radii, style: style)
            let path = shape.path(in: rect)
            XCTAssertEqual(path.boundingRect, rect)
            XCTAssertEqual(path, Path(roundedRect: rect, cornerRadii: radii, style: style))
            XCTAssertEqual(shape.layoutDirectionBehavior, .mirrors(in: .rightToLeft))
            var translated = Path()
            translated.addRoundedRect(in: rect, cornerRadii: radii, style: style, transform: .init(translationX: 7, y: 5))
            XCTAssertEqual(translated.boundingRect, rect.offsetBy(dx: 7, dy: 5))
            for (y, edges) in zip([1.25,3.25,6.25,10.25,19.25,33.25,37.25,38.75], expected) {
                let row = (0..<60).filter { path.contains(CGPoint(x: Double($0) + 0.25, y: y)) }
                XCTAssertEqual(Double(row.first ?? -10), Double(edges[0]), accuracy: 1)
                XCTAssertEqual(Double(row.last ?? -10), Double(edges[1]), accuracy: 1)
            }
        }
    }

    func testUniformCurvesAndEllipticalCornerScaling() {
        let rect = CGRect(x: 0, y: 0, width: 60, height: 40)
        let radii = RectangleCornerRadii(topLeading: 12, bottomLeading: 12, bottomTrailing: 12, topTrailing: 12)
        for style in [RoundedCornerStyle.continuous, .circular] {
            let uniform: RoundedRectangle = .rect(cornerRadius: 12, style: style)
            let uneven: UnevenRoundedRectangle = .rect(cornerRadii: radii, style: style)
            let a = uniform.path(in: rect), b = uneven.path(in: rect)
            for y in 0..<16 {
                for x in 0..<16 {
                    let point = CGPoint(x: Double(x)+0.25, y: Double(y)+0.25)
                    XCTAssertEqual(a.contains(point), b.contains(point))
                }
            }
            let capsule: Capsule = .capsule(style: style)
            XCTAssertEqual(capsule.style, style)
            XCTAssertTrue(capsule.path(in: rect).contains(CGPoint(x: 30, y: 20)))
        }
        var shape: RoundedRectangle = .rect(cornerSize: CGSize(width: 80, height: 20), style: .circular)
        XCTAssertEqual(shape.animatableData, .init(80,20))
        shape.animatableData = .init(160,40)
        let path = shape.path(in: rect)
        // Fitting 160 × 40 corners into a 60 × 40 box gives 30 × 7.5 radii.
        XCTAssertFalse(path.contains(CGPoint(x: 3, y: 2)))
        XCTAssertTrue(path.contains(CGPoint(x: 3, y: 5)))
        var translated = Path()
        translated.addRoundedRect(in: rect, cornerSize: shape.cornerSize, style: .circular, transform: .init(translationX: 5, y: 9))
        XCTAssertTrue(translated.contains(CGPoint(x: 8, y: 14)))
    }

    func testCornerAnimationComponentsAndInsetComposition() {
        var shape = UnevenRoundedRectangle(topLeadingRadius: 12, bottomLeadingRadius: 3,
                                            bottomTrailingRadius: 5, topTrailingRadius: 8, style: .circular)
        XCTAssertEqual(shape.animatableData, .init(.init(12,8), .init(5,3)))
        shape.animatableData = .init(.init(9,4), .init(7,2))
        XCTAssertEqual(shape.cornerRadii, .init(topLeading: 9, bottomLeading: 2, bottomTrailing: 7, topTrailing: 4))
        let rect = CGRect(x: 1, y: 2, width: 60, height: 40)
        let inset = shape.inset(by: 2).inset(by: 1).path(in: rect)
        let expected = Path(roundedRect: rect.insetBy(dx: 3, dy: 3),
                            cornerRadii: .init(topLeading: 6, bottomLeading: 0, bottomTrailing: 4, topTrailing: 1), style: .circular)
        XCTAssertEqual(inset.boundingRect, expected.boundingRect)
        for y in 5...13 {
            for x in 4...13 {
                let point = CGPoint(x: Double(x)+0.25, y: Double(y)+0.25)
                XCTAssertEqual(inset.contains(point), expected.contains(point))
            }
        }
    }
}
