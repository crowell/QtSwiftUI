import SwiftUI
import XCTest

private struct Anchors {
    var points: [Anchor<[CGPoint]>] = []
    var optional: [Anchor<CGPoint?>] = []
    var groups: [Anchor<[[CGRect]]>] = []
    var samePoint: [Anchor<CGPoint>] = []
}

private enum AnchorKey: PreferenceKey {
    static var defaultValue: Anchors { Anchors() }
    static func reduce(value: inout Anchors, nextValue: () -> Anchors) {
        let next = nextValue()
        value.points += next.points
        value.optional += next.optional
        value.groups += next.groups
        value.samePoint += next.samePoint
    }
}

private nonisolated func anchored<V: View>(_ view: V) -> some View {
    let corners = Anchor<[CGPoint]>.Source([.topLeading, .bottomTrailing, .point(CGPoint(x: 4, y: 7))])
    let empty = Anchor<[CGRect]>.Source([])
    let rectangles = Anchor<[CGRect]>.Source([.bounds, .rect(CGRect(x: 2, y: 3, width: 6, height: 8))])
    return view
        .anchorPreference(key: AnchorKey.self, value: corners) { Anchors(points: [$0]) }
        .transformAnchorPreference(key: AnchorKey.self, value: Anchor<CGPoint?>.Source(nil)) { $0.optional.append($1) }
        .transformAnchorPreference(key: AnchorKey.self, value: Anchor<CGPoint?>.Source(.center)) { $0.optional.append($1) }
        .transformAnchorPreference(key: AnchorKey.self, value: Anchor<[[CGRect]]>.Source([empty, rectangles])) { $0.groups.append($1) }
        .transformAnchorPreference(key: AnchorKey.self, value: .center) { $0.samePoint.append($1) }
        .transformAnchorPreference(key: AnchorKey.self, value: .unitPoint(.center)) { $0.samePoint.append($1) }
        .transformAnchorPreference(key: AnchorKey.self, value: .point(CGPoint(x: 15, y: 10))) { $0.samePoint.append($1) }
}

final class AnchorPreferenceTests: XCTestCase {
    @MainActor func testAnchorsCrossNestedReaderAndWriterTransforms() async throws {
        var inside: [[CGPoint]] = [], outside: [[CGPoint]] = []
        var insideBounds: CGRect?, outsideBounds: CGRect?
        let root = anchored(Color.clear.frame(width: 30, height: 20))
            .scaleEffect(x: 2, y: 1, anchor: .topLeading)
            .overlayPreferenceValue(AnchorKey.self) { batch in
                GeometryReader { geometry in
                    let _ = {
                        inside = batch.points.map { geometry[$0] }
                        insideBounds = batch.groups.first.map { geometry[$0][1][0] }
                    }()
                    Color.clear
                }
            }
            .rotationEffect(.degrees(45), anchor: .topLeading)
            .frame(width: 80, height: 80, alignment: .topLeading)
            .overlayPreferenceValue(AnchorKey.self) { batch in
                GeometryReader { geometry in
                    let _ = {
                        outside = batch.points.map { geometry[$0] }
                        outsideBounds = batch.groups.first.map { geometry[$0][1][0] }
                    }()
                    Color.clear
                }
            }
        let window = try await ScreenWindow(root, width: 80, height: 80)
        defer { window.close() }
        try await window.settle()
        let scaled = [CGPoint.zero, CGPoint(x: 60, y: 20), CGPoint(x: 8, y: 7)]
        let rotation = CGAffineTransform(rotationAngle: .pi / 4)
        func check(_ actual: [[CGPoint]], _ expected: [CGPoint]) throws {
            let points = try XCTUnwrap(actual.first)
            XCTAssertEqual(points.count, expected.count)
            for (point, target) in zip(points, expected) {
                XCTAssertEqual(point.x, target.x, accuracy: 0.00001)
                XCTAssertEqual(point.y, target.y, accuracy: 0.00001)
            }
        }
        try check(inside, scaled)
        try check(outside, scaled.map { $0.applying(rotation) })
        let rect = CGRect(x: 0, y: 0, width: 60, height: 20)
        // SwiftUI stores the axis-aligned bounds in window coordinates before resolving the reader.
        let windowBounds = rect.applying(rotation)
        for (value, expected) in [(insideBounds, windowBounds.applying(rotation.inverted())), (outsideBounds, windowBounds)] {
            let actual = try XCTUnwrap(value)
            XCTAssertEqual(actual.minX, expected.minX, accuracy: 0.00001)
            XCTAssertEqual(actual.minY, expected.minY, accuracy: 0.00001)
            XCTAssertEqual(actual.width, expected.width, accuracy: 0.00001)
            XCTAssertEqual(actual.height, expected.height, accuracy: 0.00001)
        }
    }

    @MainActor func testGroupResolvesNestedAndOptionalSourcesInTheReadersCoordinates() async throws {
        for direction in [LayoutDirection.leftToRight, .rightToLeft] {
            var points: [[CGPoint]] = []
            var optional: [CGPoint?] = []
            var groups: [[[CGRect]]] = []
            var unique = 0
            let view = HStack(spacing: 0) {
                anchored(Group {
                    Color.clear.frame(width: 30, height: 20)
                    Color.clear.frame(width: 50, height: 20)
                })
            }
            .padding(10)
            .overlayPreferenceValue(AnchorKey.self) { batch in
                GeometryReader { geometry in
                    let _ = {
                        points = batch.points.map { geometry[$0] }
                        optional = batch.optional.map { geometry[$0] }
                        groups = batch.groups.map { geometry[$0] }
                        unique = Set(batch.samePoint).count
                    }()
                    Color.clear
                }
            }
            .environment(\.layoutDirection, direction)
            let window = try await ScreenWindow(view, width: 100, height: 40)
            defer { window.close() }
            try await window.settle()
            let origins: [CGFloat] = direction == .leftToRight ? [10, 40] : [60, 10]
            let widths: [CGFloat] = [30, 50]
            var expectedPoints: [[CGPoint]] = []
            var expectedOptional: [CGPoint?] = []
            var expectedGroups: [[[CGRect]]] = []
            for (x, width) in zip(origins, widths) {
                expectedPoints.append([CGPoint(x: x, y: 10), CGPoint(x: x + width, y: 30), CGPoint(x: x + 4, y: 17)])
                expectedOptional += [nil, CGPoint(x: x + width / 2, y: 20)]
                expectedGroups.append([[], [CGRect(x: x, y: 10, width: width, height: 20),
                                             CGRect(x: x + 2, y: 13, width: 6, height: 8)]])
            }
            XCTAssertEqual(points, expectedPoints)
            XCTAssertEqual(optional, expectedOptional)
            XCTAssertEqual(groups, expectedGroups)
            XCTAssertEqual(unique, 4)
        }
    }
}
