import SwiftUI
import XCTest

@MainActor private final class MotionLog {
    var proxy: ScrollViewProxy?
    var offsets: [CGFloat] = []
    var phases: [ScrollPhase] = []
    var geometry: [ScrollGeometry] = []
    var velocities: [CGVector?] = []
    var simple: [ScrollPhase] = []
}

@MainActor @Observable private final class GrowingRows { var count = 2 }

private struct MovingList: View {
    let log: MotionLog
    @State var position = ScrollPosition()
    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(0..<40) { i in Color.blue.frame(height: 20).id(i) }
                    }.scrollTargetLayout()
                }
                .scrollPosition($position)
                .onScrollGeometryChange(for: CGFloat.self, of: { $0.contentOffset.y }) { _, y in log.offsets.append(y) }
                .onScrollPhaseChange { _, new, context in
                    log.phases.append(new)
                    log.geometry.append(context.geometry)
                    log.velocities.append(context.velocity)
                }
                .onScrollPhaseChange { _, new in log.simple.append(new) }
                .onAppear { log.proxy = proxy }
            }
            Button("End") { withAnimation(.linear(duration: 0.4)) { position.scrollTo(edge: .bottom) } }.frame(height: 30)
        }
    }
}

final class ScrollMotionTests: XCTestCase {
    func testPhaseValues() {
        let phases: [ScrollPhase] = [.idle, .tracking, .interacting, .decelerating, .animating]
        XCTAssertEqual(phases.map(\.debugDescription), ["idle", "tracking", "interacting", "decelerating", "animating"])
        XCTAssertEqual(phases.map(\.isScrolling), [false, true, true, true, true])
        XCTAssertEqual(Set(phases).count, 5)
    }

    @MainActor func testObservedPositionAndReaderAnimateBetweenTheirReportedEndpoints() async throws {
        let log = MotionLog()
        let window = try await ScreenWindow(MovingList(log: log), width: 160, height: 120)
        defer { window.close() }
        try await window.settle()
        XCTAssertEqual(log.phases, [.idle])
        try await window.click(80, 105)
        for _ in 0..<24 { try await window.settle() }
        XCTAssertEqual(log.phases, [.idle, .animating, .idle])
        XCTAssertEqual(log.offsets.last, 710)
        XCTAssertTrue(log.offsets.contains { (80..<630).contains($0) })
        XCTAssertEqual(log.geometry.map(\.contentOffset.y), [0, 0, 710])
        XCTAssertEqual(log.geometry.last?.containerSize.height, 90)
        log.offsets.removeAll()
        let proxy = try XCTUnwrap(log.proxy)
        withAnimation(.linear(duration: 0.4)) { proxy.scrollTo(2, anchor: .top) }
        for _ in 0..<24 { try await window.settle() }
        XCTAssertTrue(log.offsets.contains { (80..<630).contains($0) })
        XCTAssertEqual(log.offsets.last, 40)
        XCTAssertEqual(log.geometry.map(\.contentOffset.y), [0, 0, 710, 710, 40])
        XCTAssertEqual(log.velocities.compactMap { $0 }, Array(repeating: .zero, count: 5))
        proxy.scrollTo(12, anchor: .top)
        try await window.settle()
        XCTAssertEqual(log.offsets.last, 240)
        XCTAssertEqual(log.phases, [.idle, .animating, .idle, .animating, .idle])
        XCTAssertEqual(log.simple, log.phases)
    }

    @MainActor func testRetargetInFlightAndClampToDocumentExtent() async throws {
        let log = MotionLog()
        let window = try await ScreenWindow(MovingList(log: log), width: 160, height: 120)
        defer { window.close() }
        let proxy = try XCTUnwrap(log.proxy)
        withAnimation(.linear(duration: 0.6)) { proxy.scrollTo(39, anchor: .top) }
        for _ in 0..<4 { try await window.settle() }
        let midway = try XCTUnwrap(log.offsets.last)
        XCTAssertGreaterThan(midway, 40)
        XCTAssertLessThan(midway, 710)
        withAnimation(.linear(duration: 0.3)) { proxy.scrollTo(1, anchor: .top) }
        for _ in 0..<25 { try await window.settle() }
        XCTAssertEqual(log.offsets.last, 20)
        XCTAssertFalse(log.offsets.contains(710))
        withAnimation(.linear(duration: 0.15)) { proxy.scrollTo(39, anchor: .top) }
        for _ in 0..<12 { try await window.settle() }
        XCTAssertEqual(log.offsets.last, 710)
    }


    @MainActor func testReaderCanRevealNewlyLaidOutContentFromOnChange() async throws {
        let rows = GrowingRows(), log = MotionLog()
        let list = ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(0..<rows.count, id: \.self) { _ in Color.blue.frame(height: 35) }
                    Color.clear.frame(height: 0).id("end")
                }
            }
            .onChange(of: rows.count) { _, _ in
                withAnimation(.linear(duration: 0.3)) { proxy.scrollTo("end", anchor: .bottom) }
            }
            .onScrollGeometryChange(for: CGFloat.self, of: { $0.contentOffset.y }) { _, y in log.offsets.append(y) }
        }
        let window = try await ScreenWindow(list, width: 160, height: 90)
        defer { window.close() }
        rows.count = 20
        for _ in 0..<20 { try await window.settle() }
        XCTAssertEqual(log.offsets.last, 610)
        XCTAssertTrue(log.offsets.contains { (50..<550).contains($0) })
    }

    @MainActor func testWheelInterruptsAnimatedScrollAndPublishesAnIdleViewport() async throws {
        let log = MotionLog()
        let window = try await ScreenWindow(MovingList(log: log), width: 160, height: 120)
        defer { window.close() }
        try await window.click(80, 105)
        for _ in 0..<3 { try await window.settle() }
        try await window.wheel(down: false)
        let afterInput = log.offsets.last
        for _ in 0..<24 { try await window.settle() }
        XCTAssertEqual(log.offsets.last, afterInput)
        XCTAssertNotEqual(afterInput, 710)
        XCTAssertEqual(log.phases, [.idle, .animating, .interacting, .idle])
        XCTAssertEqual(log.geometry.last?.contentOffset.y, afterInput)
    }
}
