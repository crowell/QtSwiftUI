import XCTest
import SwiftUI
@testable import CallDiagnostics
#if os(Linux)
@testable import SwiftUI
import QtBridge
#else
import AppKit
#endif

@MainActor private final class PickerWindow {
    let width = 780, height = 720
    #if os(Linux)
    let host: SwiftUI.Host
    #else
    let window: NSWindow
    let hosting: NSHostingView<AnyView>
    let bitmap: NSBitmapImageRep
    var tick = 0
    #endif

    init() async throws {
        let screen = ChatColorPickerPreview()
            .environment(\.axoAnimationsDisabled, true)
            .environment(\.colorScheme, .light)
            .frame(width: CGFloat(width), height: CGFloat(height))
        #if os(Linux)
        host = Host(title: "Chat colors") { screen.resolve($0) }
        host.open(width: width, height: height)
        #else
        hosting = NSHostingView(rootView: AnyView(screen))
        window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: width, height: height),
                          styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
            bytesPerRow: 0, bitsPerPixel: 0))
        window.contentView = hosting
        window.orderFrontRegardless()
        hosting.layoutSubtreeIfNeeded()
        try await Task.sleep(for: .milliseconds(50))
        #endif
    }

    var isVisible: Bool {
        #if os(Linux)
        qs_scene_phase(host.window) != 0
        #else
        window.isVisible
        #endif
    }

    func close() {
        #if os(Linux)
        host.close()
        #else
        window.close()
        #endif
    }

    func click(_ x: Int, _ y: Int) async throws {
        #if os(Linux)
        XCTAssertEqual(qs_click_point(host.window, Int32(x), Int32(y)), 1)
        #else
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            tick += 1
            let event = try XCTUnwrap(NSEvent.mouseEvent(with: type, location: CGPoint(x: x, y: height-y), modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime + Double(tick)*0.016, windowNumber: window.windowNumber,
                context: nil, eventNumber: tick, clickCount: 1, pressure: 1))
            window.sendEvent(event)
        }
        try await Task.sleep(for: .milliseconds(50))
        #endif
    }

    func pixel(_ x: Int, _ y: Int) -> UInt32 {
        #if os(Linux)
        return qs_pixel(host.window, Int32(x), Int32(y)) & 0xffffff
        #else
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        let color = bitmap.colorAt(x: x, y: y)!.usingColorSpace(.sRGB)!
        let values = [color.redComponent, color.greenComponent, color.blueComponent].map { UInt32(($0 * 255).rounded()) }
        return values[0] << 16 | values[1] << 8 | values[2]
        #endif
    }

    func capture(_ stage: String) throws {
        guard let dir = ProcessInfo.processInfo.environment["QTSWIFTUI_PICKER_REFERENCE"] else { return }
        let url = URL(fileURLWithPath: dir).appendingPathComponent("picker-\(stage).png")
        #if os(Linux)
        XCTAssertEqual(qs_capture(host.window, url.path), 1)
        #else
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: url)
        #endif
    }
}

final class ChatColorPickerTests: XCTestCase {
    @MainActor func testSelectingAndEditingColors() async throws {
        let window = try await PickerWindow()
        defer { window.close() }
        try window.capture("initial")
        let original = window.pixel(500, 62)
        let crimson = window.pixel(162, 327), orange = window.pixel(390, 479)
        XCTAssertNotEqual(original, crimson)
        try await window.click(86, 327)
        let defaultColor = window.pixel(500, 62)
        XCTAssertNotEqual(defaultColor, original)
        try await window.click(162, 327)
        XCTAssertEqual(window.pixel(500, 62), crimson, "The outgoing bubble adopts the preset")
        try await window.click(390, 479)
        XCTAssertEqual(window.pixel(500, 62), orange, "The outgoing bubble adopts the custom color")
        try await window.click(390, 479)
        try window.capture("menu")
        try await window.click(390, 528)
        XCTAssertEqual(window.pixel(345, 260), orange, "Edit opens the selected custom color")
        try await window.click(390, 494) // Hue slider midpoint
        let edited = window.pixel(345, 260)
        XCTAssertNotEqual(edited, orange)
        try await window.click(546, 580) // Save
        XCTAssertEqual(window.pixel(500, 62), edited, "Saving updates the picker preview")
        XCTAssertEqual(window.pixel(390, 490), edited, "Saving updates the original swatch")
    }

    @MainActor func testResetAndCancel() async throws {
        let window = try await PickerWindow()
        defer { window.close() }
        let background = window.pixel(100, 695)
        try await window.click(86, 327)
        let defaultColor = window.pixel(500, 62)
        try await window.click(162, 327)
        try await window.click(100, 566) // Reset this chat
        XCTAssertEqual(window.pixel(500, 62), defaultColor)
        try await window.click(694, 479) // Add a custom color
        XCTAssertNotEqual(window.pixel(100, 695), background, "The editor dims the picker background")
        try await window.click(476, 580) // Cancel
        XCTAssertEqual(window.pixel(500, 62), defaultColor)
        try await window.click(162, 327)
        try await window.click(100, 600) // Reset all chats
        try await window.click(455, 398) // Confirm the reset
        XCTAssertEqual(window.pixel(500, 62), defaultColor)
        try await window.click(162, 327)
        try await window.click(100, 600)
        XCTAssertTrue(window.isVisible)
        try await window.click(323, 398) // Serein's alert Cancel also invokes the environment dismiss action.
        XCTAssertFalse(window.isVisible)
    }

    @MainActor func testAddingDuplicatingAndRemoving() async throws {
        let window = try await PickerWindow()
        defer { window.close() }
        try await window.click(86, 327)
        let defaultColor = window.pixel(500, 62)
        try await window.click(694, 479)
        try await window.click(546, 580)
        let added = window.pixel(500, 62)
        XCTAssertEqual(window.pixel(694, 490), added, "The new color occupies the old add button")
        try await window.click(694, 479)
        try await window.click(680, 560) // Duplicate opens an editor initialized with this color.
        XCTAssertEqual(window.pixel(345, 260), added)
        try await window.click(546, 580)
        XCTAssertEqual(window.pixel(86, 566), added, "The duplicate wraps onto the next row")
        try await window.click(86, 555)
        try await window.click(100, 665) // Delete the duplicate
        XCTAssertEqual(window.pixel(500, 62), defaultColor)
        XCTAssertEqual(window.pixel(694, 490), added, "Deleting the duplicate preserves the original")
    }
}
