import SwiftUI
import XCTest
@testable import CallDiagnostics
#if os(Linux)
import QtBridge
@testable import SwiftUI
#else
import AppKit
#endif

final class LightboxTests: XCTestCase {
    @MainActor func testSereinPhotoZoomWithQtAndAppKitPinches() async throws {
        let media = try XCTUnwrap(PhotoPreviewModel.sample.first?.image)
        var zoom: CGFloat = 1, closed = 0
        let view = LightboxZoomableImage(image: media, label: "Photo", close: { closed += 1 },
                                         zoom: Binding(get: { zoom }, set: { zoom = $0 }))
        let window = try await ScreenWindow(view, width: 500, height: 320)
        defer { window.close() }
        let center = CGPoint(x: 250, y: 160)
        try await window.pinch(at: center, factors: [1.1, 1.5])
        XCTAssertEqual(zoom, 1.5, accuracy: 0.001)
        try await window.pinch(at: center, factors: [0.8])
        XCTAssertEqual(zoom, 1.2, accuracy: 0.001)
        try await window.pinch(at: center, factors: [0.5])
        XCTAssertEqual(zoom, 1, accuracy: 0.001)
        try await window.click(250, 160)
        XCTAssertGreaterThanOrEqual(zoom, 2)
        try await window.click(250, 160)
        XCTAssertEqual(zoom, 1)
        try await window.click(10, 10)
        XCTAssertEqual(closed, 1)
    }

    @MainActor func testPhotoViewerZoomNavigationAndClose() async throws {
        // Include two items when running from a checkout without the optional upstream JPEG.
        var items = PhotoPreviewModel.sample
        XCTAssertFalse(items.isEmpty)
        if items.count == 1 { items.append(items[0]) }
        let model = PhotoPreviewModel(media: items)
        var closed = 0
        let window = try await ScreenWindow(PhotoPreview(model: model, close: { closed += 1 }), width: 760, height: 560)
        defer { window.close() }
        try window.capture("lightbox.png", directoryVariable: "QTSWIFTUI_LIGHTBOX_REFERENCE")
        func samples() -> [UInt32] { [180, 305, 460].map { window.pixel($0, 235) } }
        let fit = samples()
        #if os(Linux)
        qs_move_pointer(window.host.window, 380, 240)
        try await window.settle()
        XCTAssertEqual(qs_has_pointer_style(window.host.window, 380, 240, QSPointerZoomIn), 1)
        #endif
        try await window.click(380, 240)
        try await Task.sleep(for: .milliseconds(400))
        try await window.settle()
        XCTAssertNotEqual(samples(), fit)
        try window.capture("lightbox-zoomed.png", directoryVariable: "QTSWIFTUI_LIGHTBOX_REFERENCE")
        #if os(Linux)
        XCTAssertEqual(qs_has_pointer_style(window.host.window, 380, 240, QSPointerZoomOut), 1)
        let zoomed = samples()
        qs_move_pointer(window.host.window, 520, 270)
        try await window.settle()
        XCTAssertNotEqual(samples(), zoomed)
        #endif
        try await window.click(380, 240)
        try await Task.sleep(for: .milliseconds(400))
        try await window.settle()
        XCTAssertEqual(samples(), fit)
        XCTAssertEqual(closed, 0)
        try await window.click(432, 514)
        XCTAssertEqual(model.selected, 1)
        try await window.click(328, 514)
        XCTAssertEqual(model.selected, 0)
        try await window.click(676, 26)
        XCTAssertNotNil(model.action)
        model.action = nil
        try await window.settle()
        try await window.click(732, 26)
        XCTAssertEqual(closed, 1)
    }

    @MainActor func testShadowUsesTheSourceAlphaAndKeepsItsSize() async throws {
        let view = ZStack {
            Color.white
            Color.black.frame(width: 16, height: 16).shadow(color: .black.opacity(0.5), radius: 1, x: 12, y: 6)
            Color.black.opacity(0.5).frame(width: 6, height: 6).offset(x: -26, y: -18)
        }
        #if os(Linux)
        let window = try await ScreenWindow(view, width: 64, height: 48)
        defer { window.close() }
        let pixel = window.pixel
        #else
        let bitmap = NSBitmapImageRep(cgImage: try XCTUnwrap(ImageRenderer(content: view.frame(width: 64, height: 48)).cgImage))
        func pixel(_ x: Int, _ y: Int) -> UInt32 {
            let color = bitmap.colorAt(x: x, y: y)!.usingColorSpace(.sRGB)!
            let channels = [color.redComponent, color.greenComponent, color.blueComponent].map { UInt32(($0 * 255).rounded()) }
            return channels[0] << 16 | channels[1] << 8 | channels[2]
        }
        #endif
        XCTAssertEqual(pixel(32, 24), 0)
        let gray = pixel(45, 28)
        XCTAssertEqual(Double(gray & 255), Double(pixel(6, 6) & 255), accuracy: 2)
        XCTAssertEqual(gray >> 16, gray & 255)
        XCTAssertEqual(pixel(20, 28), 0xffffff)
    }
}
