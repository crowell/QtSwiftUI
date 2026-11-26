import SwiftUI
import XCTest

@MainActor @Observable private final class ReaderRows { var count = 120 }

@MainActor private final class ReaderLog {
    var proxy: ScrollViewProxy?
    var offsets: [String: CGPoint] = [:]
    var positions: [Int: CGRect] = [:]
    var built = Set<Int>()
}

private extension View {
    func logOffset(_ id: String, _ log: ReaderLog) -> some View {
        onScrollGeometryChange(for: CGPoint.self, of: { $0.contentOffset }) { _, offset in log.offsets[id] = offset }
    }
}

final class ScrollViewReaderTests: XCTestCase {
    @MainActor func testScrollFromOnAppearThenMoveMinimumDistanceOrAlignToAnchor() async throws {
        let log = ReaderLog()
        let view = ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    ForEach(0..<20, id: \.self) { i in Color.blue.frame(height: 20).id(i) }
                }
            }
            .scrollIndicators(.never)
            .logOffset("v", log)
            .onAppear {
                log.proxy = proxy
                proxy.scrollTo(7, anchor: .top)
            }
        }
        let window = try await ScreenWindow(view, width: 140, height: 80)
        defer { window.close() }
        try await window.settle()
        let proxy = try XCTUnwrap(log.proxy)
        XCTAssertEqual(log.offsets["v"]?.y, 140)
        proxy.scrollTo(8)
        try await window.settle()
        XCTAssertEqual(log.offsets["v"]?.y, 140)
        proxy.scrollTo(14)
        try await window.settle()
        XCTAssertEqual(log.offsets["v"]?.y, 220)
        proxy.scrollTo(7, anchor: .center)
        try await window.settle()
        XCTAssertEqual(log.offsets["v"]?.y, 110)
        proxy.scrollTo(19, anchor: .top)
        try await window.settle()
        XCTAssertEqual(log.offsets["v"]?.y, 320)
        proxy.scrollTo("missing")
        try await window.settle()
        XCTAssertEqual(log.offsets["v"]?.y, 320)
    }

    @MainActor func testSiblingScrollViewsAndHorizontalAnchor() async throws {
        let log = ReaderLog()
        let view = ScrollViewReader { proxy in
            HStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(0..<20) { i in Color.blue.frame(height: 16).id("left\(i)") }
                    }
                }.scrollIndicators(.never).logOffset("left", log).frame(width: 60)
                ScrollView(.horizontal) {
                    HStack(spacing: 0) {
                        ForEach(0..<20) { i in Color.blue.frame(width: 16, height: 30).id("right\(i)") }
                    }
                }.scrollIndicators(.never).logOffset("right", log).frame(width: 60)
            }.onAppear { log.proxy = proxy }
        }
        let window = try await ScreenWindow(view, width: 120, height: 80)
        defer { window.close() }
        let proxy = try XCTUnwrap(log.proxy)
        proxy.scrollTo("right10", anchor: .trailing)
        try await window.settle()
        XCTAssertEqual(log.offsets["right"]?.x, 116)
        XCTAssertEqual(log.offsets["left"]?.y, 0)
        proxy.scrollTo("left10", anchor: .top)
        try await window.settle()
        XCTAssertEqual(log.offsets["left"]?.y, 160)
        XCTAssertEqual(log.offsets["right"]?.x, 116)
    }

    @MainActor func testOffscreenExplicitIDAndRemovedTarget() async throws {
        let log = ReaderLog(), rows = ReaderRows()
        let view = ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(0..<rows.count, id: \.self) { i in
                        Color.orange.frame(height: 18)
                            .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .scrollView) }) { log.positions[i] = $0 }
                            .id("row-\(i)")
                    }
                }
            }.scrollIndicators(.never).logOffset("scroll", log).onAppear { log.proxy = proxy }
        }
        let window = try await ScreenWindow(view, width: 140, height: 90)
        defer { window.close() }
        let proxy = try XCTUnwrap(log.proxy)
        proxy.scrollTo("row-80", anchor: .center)
        try await window.settle()
        try await window.settle()
        XCTAssertEqual(try XCTUnwrap(log.positions[80]).midY, 45, accuracy: 1)
        rows.count = 12
        try await window.settle()
        proxy.scrollTo("row-0", anchor: .top)
        try await window.settle()
        proxy.scrollTo("row-80", anchor: .bottom)
        try await window.settle()
        XCTAssertEqual(log.offsets["scroll"]?.y, 0)
    }

    @MainActor func testProxyFindsDistantImplicitForEachIDInALazyStack() async throws {
        struct Row: View {
            let id: Int
            let log: ReaderLog
            var body: some View {
                let _ = log.built.insert(id)
                Color.blue.frame(height: 20)
                    .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .scrollView) }) { log.positions[id] = $0 }
            }
        }
        let log = ReaderLog()
        let view = ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(0..<300, id: \.self) { i in Row(id: i, log: log) }
                }
            }.scrollIndicators(.never).onAppear { log.proxy = proxy }
        }
        let window = try await ScreenWindow(view, width: 140, height: 80)
        defer { window.close() }
        let proxy = try XCTUnwrap(log.proxy)
        XCTAssertFalse(log.built.contains(249))
        proxy.scrollTo(249, anchor: .top)
        try await window.settle()
        try await window.settle()
        XCTAssertEqual(try XCTUnwrap(log.positions[249]).minY, 0, accuracy: 1)
        XCTAssertLessThan(log.built.count, 180)
    }
}
