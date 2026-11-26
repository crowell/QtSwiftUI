import SwiftUI
import XCTest
@testable import CallDiagnostics

private struct MeasureBaselines: Layout {
    struct Reading {
        var size: CGSize
        var first, last: CGFloat
        var firstExplicit, lastExplicit: CGFloat?
    }
    var record: ([Reading]) -> Void
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        CGSize(width: 320, height: 180)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        record(subviews.map {
            let d = $0.dimensions(in: .unspecified)
            return .init(size: CGSize(width: d.width, height: d.height), first: d[.firstTextBaseline],
                         last: d[.lastTextBaseline], firstExplicit: d[explicit: .firstTextBaseline], lastExplicit: d[explicit: .lastTextBaseline])
        })
        for (i, subview) in subviews.enumerated() { subview.place(at: .init(x: CGFloat(i) * 42, y: 0), proposal: .unspecified) }
    }
}

final class BaselineAlignmentTests: XCTestCase {
    @MainActor func testBundledPostScriptFaceSelectsItsWeight() async throws {
        AxoFonts.register()
        let label = Text("iiiiiiiiiiiiiiii")
        var readings: [MeasureBaselines.Reading] = []
        let view = MeasureBaselines(record: { readings = $0 }) {
            label.font(.custom("Inter-Regular", fixedSize: 20))
            label.font(.custom("Inter-SemiBold", fixedSize: 20))
            label.font(.custom("Inter", fixedSize: 20).weight(.semibold))
        }
        let window = try await ScreenWindow(view, width: 320, height: 180)
        defer { window.close() }
        XCTAssertEqual(readings.count, 3)
        guard readings.count == 3 else { return }
        XCTAssertGreaterThan(readings[1].size.width, readings[0].size.width)
        XCTAssertEqual(readings[1].size.width, readings[2].size.width, accuracy: 1)
    }

    @MainActor func testBaselinePlacesStackAndOverlayChildrenAtTheirGuides() async throws {
        var frames: [Int: CGRect] = [:]
        func marker(_ id: Int, height: CGFloat) -> some View {
            Color.red.frame(width: 8, height: height)
                .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("rows")) } action: { frames[id] = $0 }
        }
        let view = VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) { marker(0, height: 30); marker(1, height: 10) }
            ZStack(alignment: .centerLastTextBaseline) { marker(2, height: 30); marker(3, height: 10) }
            marker(4, height: 30).overlay(alignment: .leadingFirstTextBaseline) { marker(5, height: 10) }
        }.coordinateSpace(name: "rows")
        let window = try await ScreenWindow(view, width: 120, height: 120)
        defer { window.close() }
        try await window.settle()
        for i in stride(from: 0, through: 4, by: 2) {
            let tall = try XCTUnwrap(frames[i]), short = try XCTUnwrap(frames[i + 1])
            XCTAssertEqual(tall.maxY, short.maxY, accuracy: 0.5)
            XCTAssertEqual(short.minY - tall.minY, 20, accuracy: 0.5)
        }
    }

    @MainActor func testTextBaselinesThroughFramesAndStacks() async throws {
        var readings: [MeasureBaselines.Reading] = []
        let label = Text("Ag").font(.system(size: 16))
        let lines = Text("Ag\nAg").font(.system(size: 16))
        let block = Color.red.frame(width: 10, height: 20)
        let view = MeasureBaselines(record: { readings = $0 }) {
            label
            lines
            block
            label.padding(.top, 7)
            label.frame(height: 48, alignment: .bottom)
            VStack(spacing: 3) { label; lines }
            HStack(alignment: .lastTextBaseline, spacing: 0) { block; lines }
        }
        let window = try await ScreenWindow(view, width: 320, height: 180)
        defer { window.close() }
        XCTAssertEqual(readings.count, 7)
        guard readings.count == 7 else { return }
        let one = readings[0], two = readings[1], shape = readings[2]
        XCTAssertGreaterThan(one.first, 0)
        XCTAssertLessThan(one.last, one.size.height)
        XCTAssertEqual(one.first, one.last)
        XCTAssertEqual(one.first, two.first)
        XCTAssertEqual(two.last - one.last, two.size.height - one.size.height, accuracy: 1)
        XCTAssertEqual(one.firstExplicit, one.first)
        XCTAssertEqual(two.lastExplicit, two.last)
        XCTAssertNil(shape.firstExplicit)
        XCTAssertNil(shape.lastExplicit)
        XCTAssertEqual(shape.first, shape.size.height)
        XCTAssertEqual(readings[3].first, one.first + 7)
        XCTAssertEqual(readings[4].first, 48 - one.size.height + one.first)
        XCTAssertEqual(readings[5].last, one.size.height + 3 + two.last)
        XCTAssertEqual(readings[6].last, two.last)
        XCTAssertEqual(readings[6].size.height, two.size.height)
    }
}
