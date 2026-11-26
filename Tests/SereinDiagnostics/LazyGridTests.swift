import SwiftUI
import XCTest

@MainActor private final class GridLog {
    var frames: [Int: CGRect] = [:]
    var built = Set<Int>()
    var taps: [Int] = []
}

private struct CountedCell: View {
    let id: Int
    let log: GridLog
    @State var taps = 0

    var body: some View {
        let _ = log.built.insert(id)
        Color.white.frame(height: 24).onTapGesture { taps += 1; log.taps.append(taps) }
            .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { log.frames[id] = $0 }
    }
}

@MainActor @Observable private final class GridModel {
    var wide = true
}

final class LazyGridTests: XCTestCase {
    @MainActor func testChangingColumnCountPreservesIdentityAndMirrorsTracks() async throws {
        struct Sample: View {
            let model: GridModel
            let log: GridLog
            var body: some View {
                LazyVGrid(columns: [.init(.adaptive(minimum: 40), spacing: 0)], spacing: 0) {
                    ForEach(0..<6, id: \.self) { i in CountedCell(id: i, log: log) }
                }
                .frame(width: model.wide ? 120 : 80)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .environment(\.layoutDirection, .rightToLeft)
            }
        }
        let model = GridModel(), log = GridLog()
        let window = try await ScreenWindow(Sample(model: model, log: log), width: 120, height: 98)
        defer { window.close() }
        let before = try XCTUnwrap(log.frames[2])
        XCTAssertEqual(before.minX, 0)
        try await window.click(Int(before.midX), Int(before.midY))
        model.wide = false
        try await window.settle()
        let after = try XCTUnwrap(log.frames[2])
        XCTAssertEqual(after.minY, 24)
        XCTAssertGreaterThan(after.minX, before.minX)
        try await window.click(Int(after.midX), Int(after.midY))
        XCTAssertEqual(log.taps, [1, 2])
    }

    @MainActor func testSectionPinsAcrossColumnsAndConditionalCellsOccupySeparateSlots() async throws {
        let log = GridLog()
        let showColors = true
        let view = ScrollView {
            LazyVGrid(columns: [.init(), .init()], spacing: 0, pinnedViews: [.sectionHeaders, .sectionFooters]) {
                Section {
                    if showColors {
                        CountedCell(id: 0, log: log)
                        CountedCell(id: 1, log: log)
                    } else { EmptyView() }
                    ForEach(2..<62, id: \.self) { i in CountedCell(id: i, log: log) }
                } header: { Color.black.frame(height: 10) } footer: { Color.black.frame(height: 10) }
            }
        }.scrollIndicators(.hidden)
        let window = try await ScreenWindow(view, width: 120, height: 102)
        defer { window.close() }
        let first = try XCTUnwrap(log.frames[0]), second = try XCTUnwrap(log.frames[1])
        XCTAssertEqual(first.minY, second.minY)
        XCTAssertGreaterThan(second.minX, first.maxX)
        XCTAssertEqual(window.pixel(110, 4), 0)
        try await window.scroll(toEnd: true)
        XCTAssertEqual(window.pixel(110, 4), 0)
        XCTAssertEqual(window.pixel(110, 98), 0)
    }

    @MainActor func testEmptyGridKeepsItsColumnsWhenItHasNoCells() async throws {
        let log = GridLog()
        let view = VStack(spacing: 0) {
            LazyVGrid(columns: [GridItem(.fixed(40))]) { EmptyView() }
                .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { log.frames[0] = $0 }
            LazyVGrid(columns: []) { Color.blue }
                .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { log.frames[1] = $0 }
        }
        let window = try await ScreenWindow(view, width: 190, height: 60)
        defer { window.close() }
        XCTAssertEqual(try XCTUnwrap(log.frames[0]).size, CGSize(width: 190, height: 0))
        XCTAssertEqual(try XCTUnwrap(log.frames[1]).size, .zero)
    }

    @MainActor func testFixedFlexibleAndAdaptiveTracks() async throws {
        let columns: [GridItem] = [.init(.flexible(minimum: 40, maximum: 60), spacing: 10),
                                   .init(.fixed(30), spacing: 6), .init(.adaptive(minimum: 25), spacing: 4)]
        let log = GridLog()
        let view = LazyVGrid(columns: columns, spacing: 5) {
            ForEach(0..<7, id: \.self) { i in
                Color.white.frame(height: CGFloat(16 + i))
                    .onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { log.frames[i] = $0 }
            }
        }.frame(maxHeight: .infinity, alignment: .top)
        let window = try await ScreenWindow(view, width: 200, height: 74)
        defer { window.close() }
        let x: [CGFloat] = [0, 70, 106, 138 + 2.0/3, 171 + 1.0/3, 0, 70]
        let widths: [CGFloat] = [60, 30, 86.0/3, 86.0/3, 86.0/3, 60, 30]
        for i in x.indices {
            let rect = try XCTUnwrap(log.frames[i])
            XCTAssertEqual(rect.minX, x[i], accuracy: 0.01)
            XCTAssertEqual(rect.width, widths[i], accuracy: 0.01)
            XCTAssertEqual(rect.minY, i < 5 ? CGFloat(4 - i) / 2 : 25 + CGFloat(6 - i) / 2, accuracy: 0.01)
        }
        XCTAssertEqual(columns[1], GridItem(.fixed(30), spacing: 6))
    }

    @MainActor func testCappedAdaptiveTracksAlignToTrailingEdge() async throws {
        let log = GridLog()
        let view = LazyVGrid(columns: [GridItem(.adaptive(minimum: 60, maximum: 70), spacing: 5)],
                             alignment: .trailing, spacing: 6) {
            ForEach(0..<5) { i in CountedCell(id: i, log: log) }
        }.frame(maxHeight: .infinity, alignment: .top)
        let window = try await ScreenWindow(view, width: 240, height: 80)
        defer { window.close() }
        XCTAssertEqual(try XCTUnwrap(log.frames[0]), CGRect(x: 20, y: 0, width: 70, height: 24))
        XCTAssertEqual(try XCTUnwrap(log.frames[3]), CGRect(x: 20, y: 30, width: 70, height: 24))
    }

    @MainActor func testScrollGridRetainsCellStateAndLoadsDistantRowsOnDemand() async throws {
        let log = GridLog()
        let view = ScrollView {
            LazyVGrid(columns: [.init(.adaptive(minimum: 38), spacing: 0)], spacing: 0) {
                ForEach(0..<300, id: \.self) { i in CountedCell(id: i, log: log) }
            }
        }.scrollIndicators(.hidden)
        let window = try await ScreenWindow(view, width: 120, height: 99)
        defer { window.close() }
        XCTAssertFalse(log.built.contains(299))
        try await window.click(59, 12)
        try await window.scroll(toEnd: true)
        XCTAssertTrue(log.built.contains(299))
        XCTAssertLessThan(log.built.count, 180)
        try await window.scroll(toEnd: false)
        try await window.click(59, 12)
        XCTAssertEqual(log.taps, [1, 2])
    }
}
