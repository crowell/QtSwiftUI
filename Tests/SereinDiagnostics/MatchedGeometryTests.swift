import XCTest
@testable import CallDiagnostics
#if os(Linux)
import QtBridge
@testable import SwiftUI
#else
import AppKit
import SwiftUI
#endif

private struct MatchedFrames: View {
    @Namespace var group
    let properties: MatchedGeometryProperties
    let anchor: UnitPoint
    var body: some View {
        HStack(spacing: 20) {
            Color.black.matchedGeometryEffect(id: "marker", in: group, properties: properties, anchor: anchor, isSource: false)
                .frame(width: 10, height: 10)
            Color.clear.matchedGeometryEffect(id: "marker", in: group, properties: properties, anchor: .topLeading)
                .frame(width: 30, height: 20)
        }.frame(width: 100, height: 40).background(Color.white)
    }
}

final class MatchedGeometryTests: XCTestCase {
    @MainActor func testPropertiesAndIndependentAnchors() async throws {
        let cases: [(MatchedGeometryProperties, CGRect)] = [
            ([], CGRect(x: 20, y: 15, width: 10, height: 10)),
            (.position, CGRect(x: 45, y: 5, width: 10, height: 10)),
            (.size, CGRect(x: 20, y: 15, width: 30, height: 20)),
            (.frame, CGRect(x: 35, y: 0, width: 30, height: 20))
        ]
        for (properties, rect) in cases {
            let view = MatchedFrames(properties: properties, anchor: .center)
            #if os(Linux)
            let host = Host(title: "Matched") { view.resolve($0) }
            host.open(width: 100, height: 40)
            defer { host.close() }
            func dark(_ x: Int, _ y: Int) -> Bool { qs_pixel(host.window, Int32(x), Int32(y)) & 255 < 64 }
            #else
            let bitmap = NSBitmapImageRep(cgImage: try XCTUnwrap(ImageRenderer(content: view).cgImage))
            func dark(_ x: Int, _ y: Int) -> Bool { bitmap.colorAt(x: x, y: y)!.redComponent < 0.25 }
            #endif
            for x in 0..<100 { XCTAssertEqual(dark(x, Int(rect.midY)), x >= Int(rect.minX) && x < Int(rect.maxX)) }
            for y in 0..<40 { XCTAssertEqual(dark(Int(rect.midX), y), y >= Int(rect.minY) && y < Int(rect.maxY)) }
        }
    }

    #if os(Linux)
    @MainActor func testIndicatorTravelsBetweenTwoNativeButtonLabels() async {
        struct Bar: View {
            @State var second = false
            @Namespace var group
            func button(_ value: Bool) -> some View {
                Button { withAnimation(.linear(duration: 1)) { second = value } } label: {
                    Color.clear.frame(width: 40, height: 24).background {
                        if second == value { Color.black.matchedGeometryEffect(id: "selection", in: group) }
                    }
                }.buttonStyle(.plain).accessibilityLabel(value ? "Second" : "First")
            }
            var body: some View {
                HStack(spacing: 0) { button(false); button(true) }.background(Color.white)
            }
        }
        var time = 0.0
        let host = Host(title: "Matching buttons", animationClock: { time }) { Bar().resolve($0) }
        host.open(width: 80, height: 24)
        defer { host.close() }
        func span(_ now: Double) -> [Int] {
            time = now
            host.update()
            qs_flush()
            return (0..<80).filter { qs_pixel(host.window, Int32($0), 12) & 255 < 32 }
        }
        XCTAssertEqual(span(0), Array(0..<40))
        XCTAssertEqual(qs_click_named_button(host.window, "Second"), 1)
        XCTAssertEqual(span(0.5), Array(20..<60))
        XCTAssertEqual(span(1), Array(40..<80))
    }
    #endif
}
