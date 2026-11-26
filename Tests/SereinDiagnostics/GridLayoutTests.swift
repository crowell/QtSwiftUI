import SwiftUI
import XCTest

@MainActor private final class Frames {
    var values: [String: CGRect] = [:]

    func check(_ id: String, x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat,
               file: StaticString = #filePath, line: UInt = #line) throws {
        let rect = try XCTUnwrap(values[id], file: file, line: line)
        XCTAssertEqual(rect.minX, x, accuracy: 0.01, id, file: file, line: line)
        XCTAssertEqual(rect.minY, y, accuracy: 0.01, id, file: file, line: line)
        XCTAssertEqual(rect.width, w, accuracy: 0.01, id, file: file, line: line)
        XCTAssertEqual(rect.height, h, accuracy: 0.01, id, file: file, line: line)
    }
}

private extension View {
    func record(_ id: String, in frames: Frames) -> some View {
        onGeometryChange(for: CGRect.self, of: { $0.frame(in: .global) }) { frames.values[id] = $0 }
    }
    func stage() -> some View { frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading) }
}

final class GridLayoutTests: XCTestCase {
    @MainActor func testRowsShareWidthsAndFullWidthChildExpandsBothColumns() async throws {
        let f = Frames()
        let grid = Grid(horizontalSpacing: 6, verticalSpacing: 4) {
            GridRow(alignment: .bottom) {
                Color.red.frame(width: 20, height: 10).record("A", in: f)
                Color.blue.frame(width: 30, height: 18).record("B", in: f)
            }
            GridRow {
                Color.red.frame(width: 40, height: 14).record("C", in: f)
                Color.blue.frame(width: 10, height: 8).record("D", in: f)
            }
            Color.green.frame(width: 120, height: 10).record("banner", in: f)
        }.record("grid", in: f).stage()
        let window = try await ScreenWindow(grid, width: 240, height: 150)
        defer { window.close() }
        try f.check("grid", x: 0, y: 0, w: 120, h: 50)
        try f.check("A", x: 21, y: 8, w: 20, h: 10)
        try f.check("B", x: 79, y: 0, w: 30, h: 18)
        try f.check("C", x: 11, y: 22, w: 40, h: 14)
        try f.check("D", x: 89, y: 25, w: 10, h: 8)
        try f.check("banner", x: 0, y: 40, w: 120, h: 10)
    }

    @MainActor func testFlexibleSpanAndAnchorUsingAnyLayout() async throws {
        let f = Frames()
        let layout = AnyLayout(GridLayout(alignment: .topLeading, horizontalSpacing: 6, verticalSpacing: 4))
        let grid = layout {
            GridRow {
                Color.red.frame(width: 26, height: 10).record("A", in: f)
                Color.green.frame(width: 40, height: 14).record("B", in: f)
                Color.red.frame(width: 30, height: 18).record("C", in: f)
            }
            GridRow {
                Color.blue.record("span", in: f).gridCellColumns(2)
                Color.yellow.frame(width: 8, height: 16).record("anchor", in: f).gridCellAnchor(.bottomTrailing)
            }
        }.record("grid", in: f).stage()
        let window = try await ScreenWindow(grid, width: 240, height: 150)
        defer { window.close() }
        try f.check("grid", x: 0, y: 0, w: 240, h: 150)
        try f.check("B", x: 98, y: 0, w: 40, h: 14)
        try f.check("C", x: 210, y: 0, w: 30, h: 18)
        try f.check("span", x: 0, y: 22, w: 204, h: 128)
        try f.check("anchor", x: 232, y: 134, w: 8, h: 16)
    }

    @MainActor func testUnsizedDividerAndColumnAlignmentMirrorInRTL() async throws {
        let f = Frames()
        let grid = Grid(alignment: .topLeading, horizontalSpacing: 6, verticalSpacing: 4) {
            GridRow {
                Color.blue.frame(width: 36, height: 40)
                Color.red.frame(width: 40, height: 10).gridColumnAlignment(.trailing)
            }
            GridRow {
                Color.red.frame(width: 8, height: 8).record("D", in: f).gridCellAnchor(.bottomTrailing)
                Color.blue.frame(width: 20, height: 25).record("E", in: f)
            }
            Color.green.frame(height: 2).record("line", in: f).gridCellUnsizedAxes(.horizontal)
        }.record("grid", in: f).environment(\.layoutDirection, .rightToLeft).stage()
        let window = try await ScreenWindow(grid, width: 240, height: 150)
        defer { window.close() }
        try f.check("grid", x: 0, y: 0, w: 82, h: 75)
        try f.check("D", x: 46, y: 61, w: 8, h: 8)
        try f.check("E", x: 0, y: 44, w: 20, h: 25)
        try f.check("line", x: 0, y: 73, w: 82, h: 2)
    }

    @MainActor func testExplicitGuidesAlignCellsWithoutEnlargingTheirTracks() async throws {
        let f = Frames()
        let grid = Grid(alignment: .topLeading, horizontalSpacing: 4, verticalSpacing: 5) {
            GridRow {
                Color.red.frame(width: 20, height: 10).record("A", in: f)
                    .alignmentGuide(.leading) { _ in 12 }.alignmentGuide(.top) { _ in 12 }
                Color.blue.frame(width: 30, height: 15).record("B", in: f).alignmentGuide(.top) { _ in 3 }
            }
            GridRow {
                Color.green.frame(width: 30, height: 20).record("C", in: f).alignmentGuide(.leading) { _ in 4 }
            }
        }.record("grid", in: f).stage()
        let window = try await ScreenWindow(grid, width: 240, height: 150)
        defer { window.close() }
        try f.check("grid", x: 0, y: 0, w: 64, h: 40)
        try f.check("A", x: 0, y: 0, w: 20, h: 10)
        try f.check("B", x: 34, y: 9, w: 30, h: 15)
        try f.check("C", x: 8, y: 20, w: 30, h: 20)
    }

    @MainActor func testGridReadsTraitsFromTheOuterGeometryObserver() async throws {
        let f = Frames()
        let grid = Grid(alignment: .topLeading, horizontalSpacing: 4, verticalSpacing: 0) {
            GridRow {
                Color.clear.frame(width: 20, height: 8)
                Color.clear.frame(width: 30, height: 8)
                Color.clear.frame(width: 40, height: 8)
            }
            GridRow {
                Color.green.frame(height: 8).gridCellColumns(2).record("inner", in: f)
                Color.red.frame(width: 5, height: 8).record("next", in: f)
            }
            GridRow {
                Color.green.frame(height: 8).record("outer", in: f).gridCellColumns(2)
                Color.red.frame(width: 5, height: 8).record("last", in: f)
            }
        }.fixedSize().stage()
        let window = try await ScreenWindow(grid, width: 240, height: 150)
        defer { window.close() }
        try f.check("inner", x: 0, y: 8, w: 20, h: 8)
        try f.check("next", x: 24, y: 8, w: 5, h: 8)
        try f.check("outer", x: 0, y: 16, w: 54, h: 8)
        try f.check("last", x: 58, y: 16, w: 5, h: 8)
    }

    @MainActor func testFlexibleColumnStopsAtItsMaximumAndRowUsesRemainingHeight() async throws {
        let f = Frames()
        let grid = Grid(horizontalSpacing: 6, verticalSpacing: 4) {
            GridRow {
                Color.red.frame(minWidth: 30, maxWidth: 70).record("A", in: f)
                Color.green.frame(minWidth: 30).record("B", in: f)
                Color.blue.frame(width: 40).record("C", in: f)
            }
            GridRow {
                Color.red.frame(width: 20, height: 40).record("D", in: f)
                Color.blue.frame(width: 15, height: 30).record("E", in: f)
            }
        }.stage()
        let window = try await ScreenWindow(grid, width: 240, height: 150)
        defer { window.close() }
        try f.check("A", x: 0, y: 0, w: 70, h: 106)
        try f.check("B", x: 76, y: 0, w: 118, h: 106)
        try f.check("C", x: 200, y: 0, w: 40, h: 106)
        try f.check("E", x: 127.5, y: 115, w: 15, h: 30)
    }
}
