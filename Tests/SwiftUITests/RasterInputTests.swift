import CoreFoundation
@_spi(Qt) import CoreGraphics
import XCTest
@testable @_spi(Qt) import SwiftUI

final class RasterInputTests: XCTestCase {
    func testStraightAlphaPixelsAndOrientation() throws {
        var bytes = Data([0, 1, 2, 0, 253, 254, 255, 127])
        let image = try XCTUnwrap(Image(rgba8: bytes, width: 1, height: 2, scale: 2, orientation: .left))
        let source = try XCTUnwrap(image.source)
        bytes[7] = 255
        XCTAssertEqual(source.bytesPerRow, 4)
        XCTAssertEqual(source.alphaInfo, .last)
        XCTAssertEqual(image.orientation, .left)
        XCTAssertEqual(image.scale, 2)
        let copy = try XCTUnwrap(source.dataProvider?.data)
        XCTAssertEqual(source.dataProvider?.bytes, Data([0, 1, 2, 0, 253, 254, 255, 127]))
        XCTAssertEqual(CFDataGetLength(copy), 8)
        XCTAssertEqual(CFDataGetBytePtr(copy)[7], 127)
    }

    @MainActor func testPrimaryDisplayAndMissingDesktopIcons() async throws {
        let size = try XCTUnwrap(QtDesktop.primaryScreenSize)
        XCTAssertGreaterThan(size.width, 0)
        XCTAssertGreaterThan(size.height, 0)
        XCTAssertNil(QtDesktop.icon(named: "/tmp/not-a-theme-icon.png", size: 32))
        XCTAssertNil(QtDesktop.icon(named: "folder", size: -1))
    }

    @MainActor func testTintedSystemSymbolAndMissingImage() throws {
        let host = Host(title: "Symbols") { Color.white.resolve($0) }
        defer { host.close() }
        func pixels(_ name: String, _ color: Color) -> (red: Int, blue: Int) {
            var environment = EnvironmentValues()
            environment.foreground = color
            environment.font = .system(size: 30)
            var result = (red: 0, blue: 0)
            Image(systemName: name).withRaster(in: environment) { image in
                guard let bytes = image.bytes else { return }
                for y in 0..<Int(image.height) {
                    for x in 0..<Int(image.width) {
                        let offset = y * Int(image.stride) + x * 4
                        guard bytes[offset + 3] > 128 else { continue }
                        if bytes[offset] > bytes[offset + 2] { result.red += 1 }
                        else { result.blue += 1 }
                    }
                }
            }
            return result
        }
        let speaker = pixels("speaker.wave.2.fill", .red)
        XCTAssertGreaterThan(speaker.red, 60)
        XCTAssertEqual(speaker.blue, 0)
        XCTAssertEqual(pixels("speaker.wave.2.fill", .blue).blue, speaker.red)
        XCTAssertGreaterThan(pixels("star.fill", .blue).blue, pixels("star", .blue).blue)
        let missing = pixels("no.such.symbol", .blue)
        XCTAssertEqual(missing.red + missing.blue, 0)
    }

    func testAttachmentTypesAndExtensions() {
        XCTAssertEqual(UTType(filenameExtension: "JPG"), .jpeg)
        XCTAssertEqual(UTType.tiff.preferredFilenameExtension, "tiff")
        XCTAssertEqual(UTType(filenameExtension: "mp4"), .mpeg4Movie)
        XCTAssertEqual(UTType(filenameExtension: "mp4", conformingTo: .audio), .mpeg4Audio)
        XCTAssertTrue(UTType.quickTimeMovie.conforms(to: .audiovisualContent))
        XCTAssertEqual(UTType(filenameExtension: "pdf")?.preferredMIMEType, "application/pdf")
        XCTAssertNil(UTType(filenameExtension: "mp3", conformingTo: .image))
    }

    @MainActor func testIndependentDesktopWindowClosesOnce() async {
        var closes = 0, appears = 0
        let main = Host(title: "Main") { Color.white.resolve($0) }
        defer { main.close() }
        main.open(width: 120, height: 100)
        let second = QtDesktopWindow(title: "Secondary", size: CGSize(width: 100, height: 80),
                                     onClose: { closes += 1 }) { Color.red.onAppear { appears += 1 } }
        second.activate()
        second.close()
        second.close()
        XCTAssertEqual(appears, 1)
        XCTAssertEqual(closes, 1)
    }

    func testRejectsInvalidExtentsAndIncompleteOrTrailingPixels() {
        for (width, height, count) in [(0, 1, 0), (1, -1, 4), (Int.max, 2, 0), (1, Int.max, 0),
                                        (2, 2, 12), (1, 2, 9), (1, 2, 12)] {
            XCTAssertNil(Image(rgba8: Data(count: count), width: width, height: height))
        }
    }
}
