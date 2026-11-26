import SwiftUI
import XCTest

@MainActor @Observable private final class PositionedRows {
    var position = ScrollPosition(idType: Int.self)
    var id: Int?
    var count = 20
    var offset: CGPoint?
    var visible: [Int] = []
}

private struct PositionedList: View {
    @Bindable var model: PositionedRows
    let targets: Bool
    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                ForEach(0..<model.count, id: \.self) { i in Color.blue.frame(height: 20).id(i) }
            }.scrollTargetLayout(isEnabled: targets)
        }
        .scrollIndicators(.never)
        .scrollPosition($model.position, anchor: .top)
        .defaultScrollAnchor(.bottom)
        .onScrollTargetVisibilityChange(idType: Int.self) { model.visible = $0 }
        .onScrollGeometryChange(for: CGPoint.self, of: { $0.contentOffset }) { _, point in model.offset = point }
    }
}

final class ScrollPositionTests: XCTestCase {
    func testValueDestinationsAndRepeatedCommands() {
        var p = ScrollPosition(idType: Int.self), other = p
        XCTAssertNotEqual(p, ScrollPosition())
        p.scrollTo(x: 7)
        XCTAssertEqual(p.x, 7)
        XCTAssertNil(p.y)
        XCTAssertNil(p.point)
        p.scrollTo(x: 7, y: 11)
        XCTAssertEqual(p.point, CGPoint(x: 7, y: 11))
        XCTAssertNil(p.x)
        p.scrollTo(y: 9)
        XCTAssertEqual(p.y, 9)
        XCTAssertNil(p.x)
        XCTAssertNil(p.point)
        p.scrollTo(id: "row", anchor: .top)
        XCTAssertEqual(p.viewID(type: String.self), "row")
        XCTAssertNil(p.viewID(type: Int.self))
        XCTAssertFalse(p.isPositionedByUser)
        p.isPositionedByUser = true
        XCTAssertNil(p.viewID)
        p.isPositionedByUser = false
        XCTAssertTrue(p.isPositionedByUser)
        p.scrollTo(edge: .bottom)
        XCTAssertFalse(p.isPositionedByUser)
        XCTAssertEqual(p.edge, .bottom)

        var copy = other
        copy.scrollTo(edge: .bottom)
        other.scrollTo(edge: .bottom)
        XCTAssertEqual(copy, other)
        copy.scrollTo(edge: .bottom)
        XCTAssertNotEqual(copy, other)
        XCTAssertEqual(ScrollPosition(point: .zero), ScrollPosition(x: 0, y: 0))
    }

    @MainActor func testPositionsThresholdAndBottomOnAppend() async throws {
        let m = PositionedRows()
        let window = try await ScreenWindow(PositionedList(model: m, targets: true), width: 180, height: 80)
        defer { window.close() }
        try await window.settle()
        XCTAssertEqual(m.offset?.y, 320)
        XCTAssertEqual(m.visible, [16, 17, 18, 19])
        m.position.scrollTo(y: 33)
        try await window.settle()
        XCTAssertEqual(m.offset?.y, 33)
        XCTAssertEqual(m.visible, [2, 3, 4, 5])
        m.position.scrollTo(id: 9, anchor: .center)
        try await window.settle()
        XCTAssertEqual(m.offset?.y, 150)
        XCTAssertEqual(m.visible, [7, 8, 9, 10, 11])
        m.position.scrollTo(edge: .bottom)
        try await window.settle()
        m.count = 24
        try await window.settle()
        XCTAssertEqual(m.offset?.y, 400)
        XCTAssertEqual(m.visible, [20, 21, 22, 23])
    }

    @MainActor func testDisabledTargetsCanStillScrollToAnExplicitID() async throws {
        let m = PositionedRows()
        let window = try await ScreenWindow(PositionedList(model: m, targets: false), width: 180, height: 80)
        defer { window.close() }
        m.position.scrollTo(id: 12, anchor: .top)
        try await window.settle()
        XCTAssertEqual(m.offset?.y, 240)
        XCTAssertTrue(m.visible.isEmpty)
        #if os(Linux)
        try await window.wheel(down: false)
        XCTAssertTrue(m.position.isPositionedByUser)
        XCTAssertNil(m.position.viewID)
        #endif
    }

    @MainActor func testIDBindingRetainsItsProgrammaticTargetUntilUserInput() async throws {
        let m = PositionedRows()
        struct Sample: View {
            @Bindable var m: PositionedRows
            var body: some View {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(0..<m.count, id: \.self) { i in Color.blue.frame(height: 20).id(i) }
                    }.scrollTargetLayout()
                }.scrollIndicators(.never)
                    .scrollPosition(id: $m.id, anchor: .top)
                    .defaultScrollAnchor(.bottom)
                    .onScrollGeometryChange(for: CGPoint.self, of: { $0.contentOffset }) { _, v in m.offset = v }
            }
        }
        let window = try await ScreenWindow(Sample(m: m), width: 180, height: 80)
        defer { window.close() }
        try await window.settle()
        XCTAssertNil(m.id)
        XCTAssertEqual(m.offset?.y, 320)
        m.id = 8
        try await window.settle()
        XCTAssertEqual(m.offset?.y, 160)
        m.id = 19
        try await window.settle()
        XCTAssertEqual(m.offset?.y, 320)
        XCTAssertEqual(m.id, 19)
        #if os(Linux)
        try await window.wheel(down: false)
        XCTAssertNotEqual(m.id, 19)
        XCTAssertNotNil(m.id)
        #endif
    }

    @MainActor func testShortCenteredContentAndLongInitialAnchor() async throws {
        let m = PositionedRows()
        m.count = 2
        struct Sample: View {
            let m: PositionedRows
            var body: some View {
                ScrollView {
                    Color.blue.frame(height: CGFloat(m.count * 20))
                }.scrollIndicators(.never)
                    .defaultScrollAnchor(.bottom)
                    .defaultScrollAnchor(.center, for: .alignment)
                    .onScrollGeometryChange(for: CGPoint.self, of: { $0.contentOffset }) { _, point in m.offset = point }
            }
        }
        let window = try await ScreenWindow(Sample(m: m), width: 180, height: 80)
        defer { window.close() }
        try await window.settle()
        XCTAssertEqual(m.offset?.y, -20)
        m.count = 1
        try await window.settle()
        XCTAssertEqual(m.offset?.y, -30)
    }
}
