import XCTest
import SwiftUI

final class CoordinateSpaceTests: XCTestCase {
    private func check(_ actual: CGRect?, _ expected: CGRect, file: StaticString = #filePath, line: UInt = #line) throws {
        let rect = try XCTUnwrap(actual, file: file, line: line)
        XCTAssertEqual(rect.minX, expected.minX, accuracy: 1e-6, file: file, line: line)
        XCTAssertEqual(rect.minY, expected.minY, accuracy: 1e-6, file: file, line: line)
        XCTAssertEqual(rect.width, expected.width, accuracy: 1e-6, file: file, line: line)
        XCTAssertEqual(rect.height, expected.height, accuracy: 1e-6, file: file, line: line)
    }

    @MainActor func testFramesAndBoundsThroughNestedTransforms() async throws {
        for direction in [LayoutDirection.leftToRight, .rightToLeft] {
            var frames: [CGRect] = []
            var bounds: [CGRect?] = []
            var reader = GeometryReader { _ in Color.red }
            reader.content = { geometry in
                frames = [geometry.frame(in: .local), geometry.frame(in: .named("panel")),
                          geometry.frame(in: .named("outer")), geometry.frame(in: .global), geometry.frame(in: .named("unknown"))]
                bounds = [geometry.bounds(of: .named("leaf")), geometry.bounds(of: .named("panel")),
                          geometry.bounds(of: .named("outer")), geometry.bounds(of: .named("unknown"))]
                return Color.clear
            }
            let view = reader.frame(width: 40, height: 20).coordinateSpace(.named("leaf"))
                .scaleEffect(x: 2, y: 1, anchor: .topLeading)
                .padding(.leading, 20).padding(.top, 10)
                .frame(width: 100, height: 80, alignment: .topLeading).coordinateSpace(.named("panel"))
                .rotationEffect(.degrees(45), anchor: .topLeading)
                .frame(width: 180, height: 180, alignment: .topLeading).coordinateSpace(.named("outer"))
                .environment(\.layoutDirection, direction)
            let window = try await ScreenWindow(view, width: 180, height: 180)
            defer { window.close() }
            try await window.settle()
            guard frames.count == 5, bounds.count == 4 else { return XCTFail("Missing geometry observations") }
            let rtl = direction == .rightToLeft
            let local = CGRect(x: 0, y: 0, width: 40, height: 20)
            let root = CGRect(x: rtl ? 116.3603897 : -7.0710678, y: 21.2132034, width: 70.7106781, height: 70.7106781)
            try check(frames[0], local)
            try check(frames[1], CGRect(x: rtl ? 0 : 20, y: 10, width: 80, height: 20))
            for frame in frames.suffix(3) { try check(frame, root) }
            try check(bounds[0], local)
            try check(bounds[1], CGRect(x: rtl ? 0 : -10, y: -10, width: 50, height: 80))
            XCTAssertNil(bounds[2])
            XCTAssertNil(bounds[3])
        }
    }

    @MainActor func testCollapsedReflectedAndCounterRotatedSpaces() async throws {
        for scale: CGFloat in [0, -2, 1] {
            var frame: CGRect?
            var bounds: CGRect?
            let view = GeometryReader { geometry in
                let _ = frame = geometry.frame(in: .named("parent"))
                let _ = bounds = geometry.bounds(of: .named("parent"))
                Color.clear
            }.frame(width: 40, height: 20).scaleEffect(x: scale, y: 1, anchor: .topLeading)
                .rotationEffect(.degrees(scale == 1 ? 45 : 0))
                .rotationEffect(.degrees(scale == 1 ? -45 : 0))
                .frame(width: 120, height: 80, alignment: .topLeading).coordinateSpace(.named("parent"))
            let window = try await ScreenWindow(view, width: 120, height: 80)
            defer { window.close() }
            try await window.settle()
            switch scale {
            case 0:
                let width = try XCTUnwrap(frame).width
                XCTAssertGreaterThan(width, 0)
                XCTAssertLessThan(width, 1e-140)
                let inverseWidth = try XCTUnwrap(bounds).width
                XCTAssertEqual(width * inverseWidth, 40 * 120, accuracy: 1e-6)
            case -2:
                try check(frame, CGRect(x: -80, y: 0, width: 80, height: 20))
                try check(bounds, CGRect(x: -60, y: 0, width: 60, height: 80))
            default:
                try check(frame, CGRect(x: 0, y: 0, width: 40, height: 20))
                XCTAssertNil(bounds)
            }
        }
    }

    @MainActor func testNamedGroupShadowsTheOuterSpaceForEachChild() async throws {
        var samples: [Int: CGRect] = [:]
        let view = HStack(spacing: 0) {
            Group {
                ForEach([24, 48], id: \.self) { width in
                    GeometryReader { geometry in
                        let _ = samples[width] = geometry.bounds(of: .named("cells"))
                        Color.clear
                    }.frame(width: CGFloat(width), height: 20)
                }
            }.coordinateSpace(name: "cells")
        }.coordinateSpace(.named("cells"))
        let window = try await ScreenWindow(view, width: 100, height: 40)
        defer { window.close() }
        try await window.settle()
        for width in [24, 48] { try check(samples[width], CGRect(x: 0, y: 0, width: CGFloat(width), height: 20)) }
    }

    @MainActor func testScrollViewportBoundsMoveInContentCoordinates() async throws {
        var frame: CGRect?
        var nearest: CGRect?
        var vertical: CGRect?
        var horizontal: CGRect?
        let view = ScrollView(.vertical, showsIndicators: false) {
            VStack(spacing: 0) {
                Color.blue.frame(height: 40)
                GeometryReader { geometry in
                    let _ = frame = geometry.frame(in: .scrollView)
                    let _ = nearest = geometry.bounds(of: .scrollView)
                    let _ = vertical = geometry.bounds(of: .scrollView(axis: .vertical))
                    let _ = horizontal = geometry.bounds(of: .scrollView(axis: .horizontal))
                    Color.clear
                }.frame(height: 20)
                Color.red.frame(height: 140)
            }
        }
        let window = try await ScreenWindow(view, width: 100, height: 80)
        defer { window.close() }
        try await window.settle()
        for y: CGFloat in [40, -80, 40] {
            try check(frame, CGRect(x: 0, y: y, width: 100, height: 20))
            for value in [nearest, vertical] { try check(value, CGRect(x: 0, y: -y, width: 100, height: 80)) }
            XCTAssertNil(horizontal)
            try await window.scroll(toEnd: y == 40)
        }
    }

    @MainActor func testPointerInScaledNamedSpace() async throws {
        var tap: CGPoint?
        var drag: DragGesture.Value?
        let track = Color.blue.frame(width: 60, height: 40)
        let tapWindow = try await ScreenWindow(track.onTapGesture(coordinateSpace: .named("track")) { tap = $0 }
            .coordinateSpace(.named("track")).scaleEffect(x: 2, y: 1, anchor: .topLeading),
            width: 60, height: 40)
        defer { tapWindow.close() }
        try await tapWindow.click(30, 10)
        XCTAssertEqual(tap, CGPoint(x: 15, y: 10))
        let dragWindow = try await ScreenWindow(track.gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("track"))
            .onEnded { drag = $0 }).coordinateSpace(.named("track")).scaleEffect(x: 2, y: 1, anchor: .topLeading),
            width: 60, height: 40)
        defer { dragWindow.close() }
        try await dragWindow.drag(from: CGPoint(x: 10, y: 12), to: CGPoint(x: 50, y: 26))
        let value = try XCTUnwrap(drag)
        XCTAssertEqual(value.startLocation, CGPoint(x: 5, y: 12))
        XCTAssertEqual(value.location, CGPoint(x: 25, y: 26))
        XCTAssertEqual(value.translation, CGSize(width: 20, height: 14))
    }
}
