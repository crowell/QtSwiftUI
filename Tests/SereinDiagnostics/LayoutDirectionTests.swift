import SwiftUI
import class SignalI18n.Localizer
import XCTest
@testable import CallDiagnostics
#if os(Linux)
import QtBridge
@testable import SwiftUI
#else
import AppKit
#endif

private struct LeadingMark: Shape {
    func path(in r: CGRect) -> Path { Path(CGRect(x: r.minX, y: r.minY, width: 7, height: r.height)) }
}
private struct FixedMark: Shape {
    var layoutDirectionBehavior: LayoutDirectionBehavior { .fixed }
    func path(in r: CGRect) -> Path { LeadingMark().path(in: r) }
}
private struct CornerMark: Shape {
    var layoutDirectionBehavior: LayoutDirectionBehavior { .fixed }
    func path(in rect: CGRect) -> Path { Path(CGRect(x: rect.minX + 1, y: rect.minY + 1, width: 4, height: 4)) }
}

private struct SampleLayout: Layout {
    let inspect: (LayoutDirection) -> Void
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        CGSize(width: 60, height: 10)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        inspect(subviews.layoutDirection)
        subviews[0].place(at: CGPoint(x: bounds.minX + 3, y: bounds.minY), proposal: ProposedViewSize(width: 10, height: 10))
    }
}

final class LayoutDirectionTests: XCTestCase {
    @MainActor func testDirectionalLayoutAndShapePainting() async throws {
        for direction in LayoutDirection.allCases {
            var observed: LayoutDirection?
            let view = VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 0) { Color.black.frame(width: 5); Color.clear.frame(width: 55) }.frame(height: 10)
                LeadingMark().fill(.black).frame(width: 60, height: 10)
                FixedMark().fill(.black).frame(width: 60, height: 10)
                Color.black.frame(width: 6, height: 10).padding(.leading, 4).frame(width: 60, alignment: .leading)
                Color.black.frame(width: 6, height: 10).offset(x: 4).frame(width: 60)
                GeometryReader { _ in Color.black.frame(width: 6, height: 10) }.frame(width: 60, height: 10)
                SampleLayout(inspect: { observed = $0 }) { Color.black }
                Color.black.frame(width: 6, height: 10).visualEffect { v, _ in v.offset(x: 4) }.frame(width: 60)
                CornerMark().fill(.black).frame(width: 20, height: 20).rotationEffect(.degrees(90)).frame(width: 60)
            }.environment(\.layoutDirection, direction).frame(width: 60, height: 100).background(Color.white)
            let expected = direction == .leftToRight ? [0...4, 0...6, 0...6, 4...9, 31...36, 0...5, 3...12, 31...36]
                                                     : [55...59, 53...59, 0...6, 50...55, 23...28, 54...59, 47...56, 23...28]
            #if os(Linux)
            let host = Host(title: "Layout direction") { view.resolve($0) }
            defer { host.close() }
            host.open(width: 60, height: 100)
            func isBlack(_ x: Int, _ y: Int) -> Bool { qs_pixel(host.window, Int32(x), Int32(y)) & 255 < 75 }
            #else
            let bitmap = try render(view, width: 60, height: 100)
            func isBlack(_ x: Int, _ y: Int) -> Bool { bitmap.colorAt(x: x, y: y)!.redComponent < 0.3 }
            #endif
            for (row, range) in expected.enumerated() {
                XCTAssertEqual((0..<60).filter { isBlack($0, row * 10 + 5) }, Array(range), "Row \(row) in \(direction)")
            }
            XCTAssertEqual(isBlack(37, 82), direction == .leftToRight)
            XCTAssertEqual(isBlack(22, 97), direction == .rightToLeft)
            XCTAssertEqual(observed, direction)
        }
    }

    @MainActor func testSereinClearingDataInEnglishAndArabic() async throws {
        for direction in LayoutDirection.allCases {
            let rtl = direction == .rightToLeft
            let strings = Localizer(locale: rtl ? "ar" : "en")
            let screen = ClearingData(step: .deletingData).background(AxoColor.surfacePrimary)
                .environment(\.i18n, strings).environment(\.layoutDirection, direction)
                .environment(\.axoAnimationsDisabled, true).environment(\.colorScheme, .light)
                .frame(width: 680, height: 420)
            #if os(Linux)
            let host = Host(title: "Clearing data") { screen.resolve($0) }
            defer { host.close() }
            host.open(width: 680, height: 420)
            for key in ["icu:deleteAllDataProgress", "icu:ClearingData__description"] {
                XCTAssertEqual(qs_read_text(host.window, nil, strings(key)), 1)
            }
            func red(_ x: Int, _ y: Int) -> Int { Int(qs_pixel(host.window, Int32(x), Int32(y)) >> 16 & 255) }
            #else
            let bitmap = try render(screen, width: 680, height: 420)
            if let directory = ProcessInfo.processInfo.environment["QTSWIFTUI_LINK_REFERENCE"] {
                let file = URL(fileURLWithPath: directory).appendingPathComponent(rtl ? "clearing-data-ar.png" : "clearing-data.png")
                try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: file)
            }
            func red(_ x: Int, _ y: Int) -> Int { Int(bitmap.colorAt(x: x, y: y)!.redComponent * 255) }
            #endif
            let mark = rtl ? 631 : 48
            XCTAssertLessThan(red(mark, 51), 140)
            let start = rtl ? 488 : 192, end = 680 - start
            let filled = (220..<270).first { red(start, $0) < 145 && red(end, $0) > 170 }
            XCTAssertNotNil(filled, "Progress fill follows the leading edge in \(direction)")
        }
    }

    #if !os(Linux)
    @MainActor private func render<V: View>(_ view: V, width: Int, height: Int) throws -> NSBitmapImageRep {
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                                                   bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                                   colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let graphics = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: bitmap))
        ImageRenderer(content: view).render { _, draw in draw(graphics.cgContext) }
        return bitmap
    }
    #endif
}
