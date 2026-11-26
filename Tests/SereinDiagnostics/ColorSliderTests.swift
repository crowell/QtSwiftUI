import XCTest
import SwiftUI
@testable import CallDiagnostics
#if os(Linux)
import QtBridge
@testable import SwiftUI
#else
import AppKit
#endif

@Observable private final class SliderColor {
    var value = AxoColorSlider.HSLColor(hue: 240, saturation: 100, lightness: 50)
}

final class ColorSliderTests: XCTestCase {
    @MainActor func testProductionHueTrackThumbAndInput() async throws {
        for rtl in [false, true] {
            let model = SliderColor()
            let binding = Binding(get: { model.value }, set: { model.value = $0 })
            let view = AxoColorSlider.Root(channel: .hue, color: binding)
                .frame(width: 180, height: 40).background(Color.white)
                .environment(\.layoutDirection, rtl ? .rightToLeft : .leftToRight)
            #if os(Linux)
            let host = Host(title: "Hue") { view.resolve($0) }
            defer { host.close() }
            host.open(width: 180, height: 40)
            func components(_ x: Int, _ y: Int) -> [Int] {
                let value = qs_pixel(host.window, Int32(x), Int32(y))
                return [16, 8, 0].map { Int(value >> $0 & 255) }
            }
            #else
            let bitmap = NSBitmapImageRep(cgImage: try XCTUnwrap(ImageRenderer(content: view).cgImage))
            func components(_ x: Int, _ y: Int) -> [Int] {
                let value = bitmap.colorAt(x: x, y: y)!.usingColorSpace(.sRGB)!
                return [value.redComponent, value.greenComponent, value.blueComponent].map { Int($0 * 255) }
            }
            #endif
            // Sample the yellow and cyan stops away from the thumb.
            let yellow = components(30, 20), cyan = components(90, 20)
            XCTAssertGreaterThan(yellow[0], 225)
            XCTAssertGreaterThan(yellow[1], 225)
            XCTAssertLessThan(yellow[2], 45)
            XCTAssertLessThan(cyan[0], 45)
            XCTAssertGreaterThan(cyan[1], 225)
            XCTAssertGreaterThan(cyan[2], 225)
            #if os(Linux)
            XCTAssertEqual(qs_drag_pointer(host.window, 90, 20, 45, 20, 4), 1)
            XCTAssertEqual(model.value.hue, rtl ? 270 : 90, accuracy: 0.1)
            XCTAssertEqual(qs_accessible_element(host.window, "Hue", 0, "Increase"), 1)
            XCTAssertEqual(model.value.hue, rtl ? 271 : 91, accuracy: 0.1)
            XCTAssertEqual(qs_accessible_element(host.window, "Hue", 0, "Decrease"), 1)
            XCTAssertEqual(model.value.hue, rtl ? 270 : 90, accuracy: 0.1)
            #endif
        }
    }
}
