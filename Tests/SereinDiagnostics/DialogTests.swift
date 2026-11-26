import SwiftUI
import SignalI18n
import XCTest
@testable import CallDiagnostics
#if os(Linux)
import QtBridge
@testable import SwiftUI
#else
import AppKit
#endif

final class DialogTests: XCTestCase {
    @MainActor func testProductionDialogGeometryAndActions() async throws {
        var cancelled = 0, left = 0
        let en = Localizer(locale: "en")
        let dialog = AxoBaseDialog.Host {
            ConfirmLeaveCallModal(onCancel: { cancelled += 1 }, leaveCurrentCallAndStartCallingLobby: { left += 1 })
        }
        .environment(\.i18n, en)
        .frame(width: 520, height: 440)
        .background(AxoColor.surfacePrimary)
        #if os(Linux)
        let host = Host(title: "Confirm") { dialog.resolve($0) }
        defer { host.close() }
        host.open(width: 520, height: 440)
        func blue(_ x: Int, _ y: Int) -> Int { Int(qs_pixel(host.window, Int32(x), Int32(y)) & 255) }
        XCTAssertEqual(qs_read_text(host.window, nil, en("icu:CallsList__LeaveCallDialogTitle")), 1)
        XCTAssertEqual(qs_read_text(host.window, nil, en("icu:CallsList__LeaveCallDialogBody")), 1)
        XCTAssertEqual(qs_click_named_button(host.window, en("icu:CallsList__LeaveCallDialogButton--leave")), 1)
        XCTAssertEqual(left, 1)
        XCTAssertEqual(cancelled, 0)
        #else
        let renderer = ImageRenderer(content: dialog.environment(\.axoStaticRendering, true).environment(\.colorScheme, .light))
        let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 520, pixelsHigh: 440,
                                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                                     isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
        let graphics = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: bitmap))
        renderer.render { _, draw in draw(graphics.cgContext) }
        if let path = ProcessInfo.processInfo.environment["QTSWIFTUI_DIALOG_REFERENCE"] {
            try bitmap.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        }
        func blue(_ x: Int, _ y: Int) -> Int {
            Int(((bitmap.colorAt(x: x, y: y)?.blueComponent ?? 0) * 255).rounded())
        }
        #endif
        let backdrop = blue(40, 220)
        XCTAssertGreaterThan(blue(118, 220), backdrop + 30)
        XCTAssertGreaterThan(blue(401, 220), backdrop + 30)
        XCTAssertLessThan(blue(113, 220), backdrop)
        #if os(Linux)
        XCTAssertEqual(qs_click_named_button(host.window, en("icu:cancel")), 1)
        XCTAssertEqual(left, 1)
        XCTAssertEqual(cancelled, 1)
        #endif
    }
}
