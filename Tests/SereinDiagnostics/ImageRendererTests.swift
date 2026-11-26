import SwiftUI
import XCTest
import ImagePNG
import SignalI18n
#if canImport(Vision)
import Vision
#endif
@testable import CallDiagnostics

@MainActor @Observable private final class Ink {
    var color = Color.black
    var appearances = 0
}

final class ImageRendererTests: XCTestCase {
    @MainActor func testNaturalAndProposedSizesAndDisplayScale() async throws {
        struct Sample: View {
            @Environment(\.displayScale) var density
            var body: some View { Color.red.frame(width: 4 * density, height: 3) }
        }
        let natural = ImageRenderer(content: Color.clear)
        XCTAssertEqual(natural.proposedSize, .unspecified)
        XCTAssertFalse(natural.isOpaque)
        XCTAssertEqual(natural.scale, 1)
        XCTAssertEqual(natural.cgImage?.width, 10)
        let scaled = ImageRenderer(content: Sample())
        scaled.scale = 2.5
        scaled.proposedSize = .init(width: 50, height: 20)
        let image = try XCTUnwrap(scaled.cgImage)
        XCTAssertEqual(image.width, 25)
        XCTAssertEqual(image.height, 8)
        let empty = ImageRenderer(content: EmptyView())
        empty.proposedSize = .init(width: 80, height: 40)
        XCTAssertNil(empty.cgImage)
        let fractional = ImageRenderer(content: Color.black)
        fractional.proposedSize = .init(width: 13.4, height: 7.2)
        fractional.scale = 3
        XCTAssertEqual(fractional.cgImage?.width, 41)
        XCTAssertEqual(fractional.cgImage?.height, 22)
    }

    @MainActor func testRepeatedRenderingUsesTheCurrentContentAndKeepsItsIdentity() async throws {
        struct Stamp: View {
            let ink: Ink
            var body: some View {
                ink.color.frame(width: 8, height: 6).onAppear { ink.appearances += 1 }
            }
        }
        let ink = Ink()
        let renderer = ImageRenderer(content: Stamp(ink: ink))
        let first = try XCTUnwrap(renderer.cgImage)
        XCTAssertEqual(try XCTUnwrap(MediaEditorExport.pixels(first)).pixel(x: 2, y: 2).r, 0)
        ink.color = Color(.sRGB, red: 1, green: 0, blue: 0)
        renderer.scale = 2
        try await Task.sleep(for: .milliseconds(40))
        let second = try XCTUnwrap(renderer.cgImage)
        XCTAssertEqual(second.width, 16)
        XCTAssertEqual(try XCTUnwrap(MediaEditorExport.pixels(second)).pixel(x: 4, y: 4).r, 255)
        XCTAssertEqual(ink.appearances, 1)
    }

    @MainActor func testPremultipliedAlphaAndOpaqueOutput() async throws {
        let red = Color(.sRGB, red: 1, green: 0, blue: 0, opacity: 0.5)
        let card = ZStack(alignment: .topLeading) {
            Color.clear
            red.frame(width: 4, height: 3)
        }.frame(width: 9, height: 7)
        for opaque in [false, true] {
            let renderer = ImageRenderer(content: card)
            renderer.scale = 2
            renderer.isOpaque = opaque
            let image = try XCTUnwrap(renderer.cgImage)
            XCTAssertEqual(image.width, 18)
            XCTAssertEqual(image.height, 14)
            let data = try XCTUnwrap(MediaEditorExport.pixels(image))
            let inside = data.pixel(x: 3, y: 2), outside = data.pixel(x: 13, y: 11)
            XCTAssertEqual(Int(inside.r), opaque ? 128 : 255, accuracy: 2)
            XCTAssertEqual(Int(inside.a), opaque ? 255 : 128, accuracy: 1)
            XCTAssertEqual(inside.g, 0)
            XCTAssertEqual(outside.a, opaque ? 255 : 0)
        }
    }

    @MainActor func testSereinExportPaintsTheUsernameCard() async throws {
        let png = try XCTUnwrap(UsernameLinkCard.png(link: UsernameCardPreview.link, username: UsernameCardPreview.username,
                                                      color: .blue, i18n: Localizer(locale: "en")))
        let pixels = try PNGDecoder.decode(png).stillImage
        func components(_ x: Int, _ y: Int) -> [UInt8] {
            let p = pixels.pixel(x: x * 3, y: y * 3)
            return [p.r, p.g, p.b, p.a]
        }
        XCTAssertEqual(components(15, 15), [236, 240, 251, 255])
        XCTAssertEqual(components(74, 230), [80, 110, 205, 255])
        XCTAssertEqual(components(110, 180), [255, 255, 255, 255])
        #if canImport(Vision)
        var samples = [Data(png)]
        if let path = ProcessInfo.processInfo.environment["QTSWIFTUI_UBUNTU_USERNAME_CARD"] {
            samples.append(try Data(contentsOf: URL(fileURLWithPath: path)))
        }
        for sample in samples {
            let request = VNDetectBarcodesRequest()
            request.symbologies = [.qr]
            try VNImageRequestHandler(data: sample).perform([request])
            XCTAssertEqual(request.results?.compactMap(\.payloadStringValue), [UsernameCardPreview.link])
        }
        #endif
        if let folder = ProcessInfo.processInfo.environment["QTSWIFTUI_USERNAME_REFERENCE"] {
            try Data(png).write(to: URL(fileURLWithPath: folder).appendingPathComponent("username-card.png"))
        }
    }
}
