import SwiftUI
import XCTest

final class KerningTests: XCTestCase {
    @MainActor func testAttributedSpacingAndTrackingPrecedence() async throws {
        func width(_ text: Text) throws -> Int {
            let renderer = ImageRenderer(content: text.font(.system(size: 18)).fixedSize())
            renderer.scale = 1
            return try XCTUnwrap(renderer.cgImage).width
        }
        let plain = AttributedString("MMMM")
        var shifted = plain
        let middle = try XCTUnwrap(shifted.range(of: "MM"))
        shifted[middle].kern = 6
        XCTAssertEqual(try width(Text(shifted)) - width(Text(plain)), 12, accuracy: 1)
        let all = Text(verbatim: "MMMM")
        XCTAssertGreaterThan(try width(all.kerning(6)), try width(all))
        XCTAssertEqual(try width(all.kerning(9).tracking(2)), try width(all.tracking(2)))
        XCTAssertEqual(try width(all.tracking(2).kerning(9)), try width(all.tracking(2)))
        XCTAssertEqual(AttributeScopes.SwiftUIAttributes.KerningAttribute.name, "SwiftUI.Kern")
        XCTAssertEqual(AttributeScopes.SwiftUIAttributes.TrackingAttribute.name, "SwiftUI.Tracking")
    }
}
