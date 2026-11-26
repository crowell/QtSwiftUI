import XCTest
import SwiftUI
@testable import CallDiagnostics
#if os(Linux)
@testable import SwiftUI
import QtBridge
#else
import AppKit
#endif

@MainActor final class ScreenWindow {
    let width: Int, height: Int
    #if os(Linux)
    let host: SwiftUI.Host
    #else
    let window: NSWindow
    let hosting: NSHostingView<AnyView>
    let bitmap: NSBitmapImageRep
    var tick = 0
    #endif

    init(_ content: some View, width: Int, height: Int) async throws {
        self.width = width
        self.height = height
        let screen = content
            .environment(\.axoAnimationsDisabled, true)
            .environment(\.colorScheme, .light)
            .frame(width: CGFloat(width), height: CGFloat(height))
        #if os(Linux)
        host = Host(title: "Serein") { screen.resolve($0) }
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
        try await pointer(x, y, down: true)
        try await pointer(x, y, down: false)
        #endif
    }

    func pointer(_ x: Int, _ y: Int, down: Bool) async throws {
        #if os(Linux)
        XCTAssertEqual(qs_pointer_button(host.window, Int32(x), Int32(y), down ? 1 : 0), 1)
        #else
        tick += 1
        let event = try XCTUnwrap(NSEvent.mouseEvent(with: down ? .leftMouseDown : .leftMouseUp, location: CGPoint(x: x, y: height-y),
            modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime + Double(tick)*0.016, windowNumber: window.windowNumber,
            context: nil, eventNumber: tick, clickCount: 1, pressure: 1))
        window.sendEvent(event)
        try await Task.sleep(for: .milliseconds(35))
        #endif
    }

    func type(_ text: String) async throws {
        #if os(Linux)
        XCTAssertEqual(text.withCString { qs_commit_text(host.window, $0, text.utf8.count) }, 1)
        #else
        let editor = try XCTUnwrap(window.firstResponder as? NSTextView)
        editor.insertText(text, replacementRange: editor.selectedRange())
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

    func capture(_ filename: String, directoryVariable: String) throws {
        guard let dir = ProcessInfo.processInfo.environment[directoryVariable] else { return }
        let url = URL(fileURLWithPath: dir).appendingPathComponent(filename)
        #if os(Linux)
        XCTAssertEqual(qs_capture(host.window, url.path), 1)
        #else
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: url)
        #endif
    }
}
