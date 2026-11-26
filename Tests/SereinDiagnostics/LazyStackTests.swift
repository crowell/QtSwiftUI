import XCTest
import SwiftUI

@MainActor private final class RowLog {
    var built = Set<Int>()
    var appeared = Set<Int>()
    var taps: [Int] = []
}

private struct CountedRow: View {
    let index: Int
    let log: RowLog
    @State private var taps = 0
    var body: some View {
        let _ = log.built.insert(index)
        Color.white.frame(height: 24)
            .onTapGesture { taps += 1; log.taps.append(taps) }
            .onAppear { log.appeared.insert(index) }
    }
}

final class LazyStackTests: XCTestCase {
    @MainActor func testScrollMaterializesRowsAndKeepsStateByID() async throws {
        let log = RowLog()
        let view = ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(0..<200, id: \.self) { index in CountedRow(index: index, log: log) }
            }
        }.scrollIndicators(.hidden)
        let window = try await ScreenWindow(view, width: 120, height: 102)
        defer { window.close() }
        XCTAssertTrue(log.appeared.contains(0))
        XCTAssertFalse(log.built.contains(199))
        try await window.click(20, 12)
        try await window.scroll(toEnd: true)
        XCTAssertTrue(log.appeared.contains(199))
        XCTAssertLessThan(log.built.count, 100)
        try await window.scroll(toEnd: false)
        try await window.click(20, 12)
        XCTAssertEqual(log.taps, [1, 2])
    }

    @MainActor func testHeadersAndFootersPinInsideTheirOwnSection() async throws {
        let view = ScrollView {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders, .sectionFooters]) {
                Section {
                    ForEach(0..<30) { _ in Color.white.frame(height: 20) }
                } header: { Color.black.frame(height: 12) } footer: { Color.black.frame(height: 10) }
                Section {
                    ForEach(0..<30) { _ in Color.black.frame(height: 20) }
                } header: { Color.white.frame(height: 12) } footer: { Color.white.frame(height: 10) }
            }
        }.scrollIndicators(.hidden)
        let window = try await ScreenWindow(view, width: 120, height: 100)
        defer { window.close() }
        XCTAssertEqual(window.pixel(50, 5), 0)
        XCTAssertEqual(window.pixel(50, 50), 0xffffff)
        XCTAssertEqual(window.pixel(50, 95), 0)
        try await window.scroll(toEnd: true)
        XCTAssertEqual(window.pixel(50, 5), 0xffffff)
        XCTAssertEqual(window.pixel(50, 50), 0)
        XCTAssertEqual(window.pixel(50, 95), 0xffffff)
    }
}
