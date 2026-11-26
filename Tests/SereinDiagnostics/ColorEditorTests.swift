import XCTest
import SwiftUI
import SignalI18n
@testable import CallDiagnostics
#if os(Linux)
@testable import SwiftUI
import QtBridge
#else
import AppKit
#endif

final class ColorEditorTests: XCTestCase {
    @MainActor func testProductionDialogAndGradientControls() async throws {
        let strings = Localizer(locale: "en")
        var saves: [BubbleColor] = []
        var closes = 0
        let screen = AxoBaseDialog.Host {
            CustomColorEditorDialog(initialGradient: (0xB36409, 0x852CB1, 135),
                                    onClose: { closes += 1 }, onSave: { saves.append($0) })
        }
        .background(AxoColor.surfacePrimary)
        .environment(\.conversationListNow, Date(timeIntervalSince1970: 1_793_793_600))
        .environment(\.timeZone, TimeZone(secondsFromGMT: 0)!)
        .environment(\.i18n, strings)
        .environment(\.colorScheme, .light)
        .environment(\.axoAnimationsDisabled, true)
        .frame(width: 520, height: 620)
        #if os(Linux)
        let host = Host(title: "Custom Color") { screen.resolve($0) }
        defer { host.close() }
        host.open(width: 520, height: 620)
        func rgb(_ x: Int, _ y: Int) -> [Int] {
            let value = qs_pixel(host.window, Int32(x), Int32(y))
            return [16,8,0].map { Int(value >> $0 & 255) }
        }
        #else
        let renderer = ImageRenderer(content: screen.environment(\.axoStaticRendering, true))
        let image = NSBitmapImageRep(cgImage: try XCTUnwrap(renderer.cgImage))
        if let path = ProcessInfo.processInfo.environment["QTSWIFTUI_EDITOR_REFERENCE"] {
            try XCTUnwrap(image.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: path))
        }
        func rgb(_ x: Int, _ y: Int) -> [Int] {
            let color = image.colorAt(x: x, y: y)!.usingColorSpace(.sRGB)!
            return [color.redComponent, color.greenComponent, color.blueComponent].map { Int($0 * 255) }
        }
        #endif
        let orange = rgb(166,182), purple = rgb(353,369)
        XCTAssertGreaterThan(orange[0], orange[2] + 80)
        XCTAssertGreaterThan(purple[2], purple[1] + 65)
        #if os(Linux)
        func click(_ x: Int, _ y: Int) async throws {
            XCTAssertEqual(qs_click_point(host.window, Int32(x), Int32(y)), 1)
        }
        func dragHue() async throws { XCTAssertEqual(qs_drag_pointer(host.window, 200, 444, 260, 444, 6), 1) }
        #else
        let hosting = NSHostingView(rootView: screen)
        let window = NSWindow(contentRect: CGRect(x: 100, y: 100, width: 520, height: 620),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }
        hosting.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(50))
        var tick = 0
        func mouse(_ type: NSEvent.EventType, _ x: Int, _ y: Int) throws {
            tick += 1
            let event = try XCTUnwrap(NSEvent.mouseEvent(with: type, location: CGPoint(x: x, y: 620 - y), modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime + Double(tick) * 0.016,
                windowNumber: window.windowNumber, context: nil, eventNumber: tick, clickCount: 1, pressure: 1))
            window.sendEvent(event)
        }
        func click(_ x: Int, _ y: Int) async throws {
            try mouse(.leftMouseDown, x, y)
            try mouse(.leftMouseUp, x, y)
            try await Task.sleep(for: .milliseconds(30))
        }
        func dragHue() async throws {
            try mouse(.leftMouseDown, 200, 444)
            for i in 1...6 { try mouse(.leftMouseDragged, 200 + i*10, 444) }
            try mouse(.leftMouseUp, 260, 444)
            try await Task.sleep(for: .milliseconds(30))
        }
        #endif
        func gradient() throws -> CSSLinearGradient { try XCTUnwrap(saves.last?.data.gradient) }
        try await click(416, 529)
        XCTAssertEqual(try gradient().deg, 135)
        #if os(Linux)
        XCTAssertEqual(qs_accessible_element(host.window, strings("icu:GradientDial__knob-start"), 0, "Increase"), 1)
        try await click(416, 529)
        XCTAssertEqual(try gradient().deg, 134)
        #endif
        // Both knobs claim the same layout frame. Only the selected endpoint should change.
        try await click(353, 369)
        try await dragHue()
        try await click(416, 529)
        let changed = try gradient()
        XCTAssertEqual(changed.start, CustomColorEditorState(gradient: (0xB36409, 0x852CB1, 135)).start.rgba)
        XCTAssertGreaterThan(changed.end.g, changed.end.r + 0.3)
        try await click(167, 125)
        try await click(416, 529)
        guard case .solid = saves.last else { return XCTFail("Solid tab must save a solid color") }
        try await click(348, 529)
        XCTAssertEqual(closes, saves.count + 1)
    }
}
