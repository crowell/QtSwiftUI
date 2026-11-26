import CoreFoundation
@_spi(Qt) import CoreGraphics
import XCTest
@testable @_spi(Qt) import SwiftUI

final class RasterInputTests: XCTestCase {
    func testStraightAlphaPixelsAndOrientation() throws {
        var bytes = Data([0, 1, 2, 0, 253, 254, 255, 127])
        let image = try XCTUnwrap(Image(rgba8: bytes, width: 1, height: 2, scale: 2, orientation: .left))
        bytes[7] = 255
        XCTAssertEqual(image.source.bytesPerRow, 4)
        XCTAssertEqual(image.source.alphaInfo, .last)
        XCTAssertEqual(image.orientation, .left)
        XCTAssertEqual(image.scale, 2)
        let copy = try XCTUnwrap(image.source.dataProvider?.data)
        XCTAssertEqual(image.source.dataProvider?.bytes, Data([0, 1, 2, 0, 253, 254, 255, 127]))
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

    func testRejectsInvalidExtentsAndIncompleteOrTrailingPixels() {
        for (width, height, count) in [(0, 1, 0), (1, -1, 4), (Int.max, 2, 0), (1, Int.max, 0),
                                        (2, 2, 12), (1, 2, 9), (1, 2, 12)] {
            XCTAssertNil(Image(rgba8: Data(count: count), width: width, height: height))
        }
    }
}
