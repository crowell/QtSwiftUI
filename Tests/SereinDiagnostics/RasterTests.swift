import XCTest
import SwiftUI
import CoreFoundation
#if os(Linux)
import QtBridge
@testable import SwiftUI
#else
import AppKit
#endif

private struct SizeProbe: Layout {
    let check: (LayoutSubview) -> Void
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        check(subviews[0])
        return CGSize(width: 64, height: 64)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews[0].place(at: bounds.origin, proposal: ProposedViewSize(bounds.size))
    }
}

@MainActor final class RasterTests: XCTestCase {
    private let colors: [UInt32] = [0xff0000, 0x00ff00, 0x0000ff, 0xffff00, 0xff00ff, 0x00ffff]

    private func image() throws -> CGImage {
        var bytes: [UInt8] = []
        for row in [colors.prefix(3), colors.suffix(3)] {
            for pixel in row { bytes += [UInt8(pixel >> 16), UInt8((pixel >> 8) & 255), UInt8(pixel & 255), 255] }
            bytes += [77, 88, 99, 111] // Padding is outside the three visible pixels.
        }
        let data = try XCTUnwrap(CFDataCreate(nil, bytes, bytes.count))
        return try XCTUnwrap(CGImage(width: 3, height: 2, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: 16,
                                     space: try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB)), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
                                     provider: try XCTUnwrap(CGDataProvider(data: data)), decode: nil, shouldInterpolate: false, intent: .defaultIntent))
    }

    private func sample<V: View>(_ view: V, width: Int, height: Int, points: [(Int, Int)]) throws -> [UInt32] {
        let root = view.frame(width: CGFloat(width), height: CGFloat(height)).environment(\.colorScheme, .light)
        #if os(Linux)
        let host = Host(title: "Raster") { root.resolve($0) }
        defer { host.close() }
        host.open(width: width, height: height)
        return points.map { qs_pixel(host.window, Int32($0.0), Int32($0.1)) & 0xffffff }
        #else
        let image = try XCTUnwrap(ImageRenderer(content: root).cgImage)
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        try bytes.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                                  bytesPerRow: 4 * width, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        }
        return points.map { x, y in
            let i = (y * width + x) * 4
            return UInt32(bytes[i]) << 16 | UInt32(bytes[i+1]) << 8 | UInt32(bytes[i+2])
        }
        #endif
    }

    func testMagnificationResolvesOriginalImagePixels() throws {
        let photo = Image(decorative: try image(), scale: 1).resizable().interpolation(.none)
            .frame(width: 1, height: 2).scaleEffect(x: 3, y: 1)
        let points = (0..<2).flatMap { row in (0..<3).map { ($0, row) } }
        XCTAssertEqual(try sample(photo, width: 3, height: 2, points: points), colors)
    }

    func testPaddedRGBAInEveryImageOrientation() async throws {
        let cg = try image()
        let expected = [[0,1,2,3,4,5], [2,1,0,5,4,3], [5,4,3,2,1,0], [3,4,5,0,1,2],
                        [2,5,1,4,0,3], [0,3,1,4,2,5], [3,0,4,1,5,2], [5,2,4,1,3,0]]
        for (index, orientation) in Image.Orientation.allCases.enumerated() {
            let w = index < 4 ? 3 : 2, h = index < 4 ? 2 : 3
            let view = Image(decorative: cg, scale: 1, orientation: orientation).resizable().interpolation(.none)
            let points = (0..<h).flatMap { y in (0..<w).map { x in (x * 12 + 6, y * 12 + 6) } }
            XCTAssertEqual(try sample(view, width: w * 12, height: h * 12, points: points),
                           expected[index].map { colors[$0] }, "\(orientation)")
        }
    }

    func testCapInsetsAndRepeatingTile() async throws {
        let cg = try image()
        let fixedCaps = Image(decorative: cg, scale: 1).resizable(capInsets: EdgeInsets(top: 0, leading: 1, bottom: 0, trailing: 1))
            .interpolation(.none)
        XCTAssertEqual(try sample(fixedCaps, width: 30, height: 20, points: [(0,3),(1,3),(28,3),(29,3)]),
                       [colors[0],colors[1],colors[1],colors[2]])
        let tiled = Image(decorative: cg, scale: 1).resizable(resizingMode: .tile).interpolation(.none)
        XCTAssertEqual(try sample(tiled, width: 30, height: 20, points: [(0,0),(2,1),(3,2),(29,19)]),
                       [colors[0],colors[5],colors[0],colors[5]])
    }

    func testAspectProposalsAndImageScale() async throws {
        let cg = try image()
        let photo = Image(decorative: cg, scale: 0.5)
        let proposals: [ProposedViewSize] = [.unspecified, .init(width: 60, height: nil), .init(width: nil, height: 30),
                                              .init(width: 60, height: 30), .zero]
        func check<V: View>(_ view: V, expecting sizes: [CGSize]) throws {
            var measured = false
            let probe = SizeProbe(check: { child in
                measured = true
                XCTAssertEqual(proposals.map { child.sizeThatFits($0) }, sizes)
            }) { view }
            _ = try sample(probe, width: 64, height: 64, points: [])
            XCTAssertTrue(measured)
        }
        let natural = CGSize(width: 6, height: 4)
        try check(photo, expecting: Array(repeating: natural, count: 5))
        let wide = CGSize(width: 60, height: 40), tall = CGSize(width: 45, height: 30)
        try check(photo.resizable().scaledToFit(), expecting: [natural, wide, tall, tall, .zero])
        try check(photo.resizable().scaledToFill(), expecting: [natural, wide, tall, wide, .zero])
        try check(Color.black.aspectRatio(CGSize(width: 3, height: 2), contentMode: .fit),
                  expecting: [CGSize(width: 10, height: 10), wide, tall, tall, .zero])
    }

    func testGradientInterpolationAndSpread() async throws {
        let red = Color(.sRGB, red: 1, green: 0, blue: 0), blue = Color(.sRGB, red: 0, green: 0, blue: 1)
        let gradient = Gradient(colors: [red, blue])
        let device = AnyShapeStyle(.linearGradient(gradient.colorSpace(.device), startPoint: .leading, endPoint: .trailing))
        let perceptual = AnyShapeStyle(LinearGradient(gradient: gradient, startPoint: .leading, endPoint: .trailing))
        func channels(_ rgb: UInt32, near expected: [Int], tolerance: Double = 3) {
            for (index, shift) in [16, 8, 0].enumerated() {
                XCTAssertEqual(Double(rgb >> shift & 255), Double(expected[index]), accuracy: tolerance)
            }
        }
        for (style, mid) in [(device, [128,0,128]), (perceptual, [141,83,163])] {
            let rgb = try sample(Rectangle().fill(style), width: 101, height: 10, points: [(50,5)])
            channels(rgb[0], near: mid)
        }
        let start = CGPoint(x: 25, y: 0), end = CGPoint(x: 75, y: 0)
        for (options, left, middle) in [(GraphicsContext.GradientOptions(), [255,0,0], [125,0,130]),
                                          (.repeat, [74,0,181], [125,0,130]),
                                          (.mirror, [182,0,74], [125,0,130]),
                                          (.linearColor, [255,0,0], [186,0,190])] {
            let canvas = Canvas { context, size in
                context.fill(Path(CGRect(origin: .zero, size: size)),
                             with: .linearGradient(gradient, startPoint: start, endPoint: end, options: options))
            }
            let rgb = try sample(canvas, width: 101, height: 10, points: [(10,5),(50,5)])
            channels(rgb[0], near: left)
            channels(rgb[1], near: middle)
        }
        let typed = Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .linearGradient(AnyGradient(gradient), startPoint: start, endPoint: end))
        }
        channels(try sample(typed, width: 101, height: 10, points: [(50,5)])[0], near: [138,83,164])
        let vertical = try sample(Rectangle().foregroundStyle(gradient), width: 101, height: 101, points: [(20,50),(80,50)])
        for value in vertical { channels(value, near: [141,83,163]) }
    }

    func testGradientAsViewShapeStyleAndCanvasShading() async throws {
        let gradient = LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black.opacity(0.6), location: 1)],
                                      startPoint: .leading, endPoint: .trailing)
        let path = Path(CGRect(x: 0, y: 0, width: 100, height: 12))
        let canvas = Canvas { context, _ in context.fill(path, with: .style(gradient)) }
        for view in [AnyView(gradient), AnyView(Rectangle().fill(gradient)), AnyView(canvas)] {
            let points = [(0,5),(49,5),(99,5)]
            for rtl in [false, true] {
                let samples = try sample(view.background(Color.white).environment(\.layoutDirection, rtl ? .rightToLeft : .leftToRight),
                                         width: 100, height: 12, points: points)
                for (actual, expected) in zip(samples, rtl ? [103,180,254] : [254,180,103]) {
                    XCTAssertEqual(Double(actual & 255), Double(expected), accuracy: 3)
                }
            }
        }
    }
}
