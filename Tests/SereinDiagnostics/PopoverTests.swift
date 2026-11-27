import SwiftUI
import XCTest
#if os(Linux)
@testable import SwiftUI
import QtBridge
#else
import AppKit
#endif

extension ScreenWindow {
    var popoverFrame: CGRect? {
        #if os(Linux)
        let frame = qs_active_popover_frame(host.window)
        guard frame.width > 0 else { return nil }
        return CGRect(x: frame.x, y: frame.y, width: frame.width, height: frame.height)
        #else
        guard let popup = window.childWindows?.last(where: { $0.isVisible }) else { return nil }
        let frame = window.convertFromScreen(popup.frame)
        return CGRect(x: frame.minX, y: CGFloat(height) - frame.maxY, width: frame.width, height: frame.height)
        #endif
    }

    func settlePopover() async throws {
        #if os(macOS)
        try await Task.sleep(for: .milliseconds(280))
        #endif
        try await settle()
    }

    func clickPopover(_ x: Int, _ y: Int) async throws {
        #if os(Linux)
        XCTAssertEqual(qs_click_popover(host.window, Int32(x), Int32(y)), 1)
        #else
        let popup = try XCTUnwrap(window.childWindows?.last(where: { $0.isVisible }))
        for kind in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            tick += 1
            let event = try XCTUnwrap(NSEvent.mouseEvent(with: kind,
                location: CGPoint(x: CGFloat(x), y: popup.frame.height - CGFloat(y)), modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: popup.windowNumber, context: nil,
                eventNumber: tick, clickCount: 1, pressure: 1))
            popup.sendEvent(event)
            try await Task.sleep(for: .milliseconds(30))
        }
        #endif
        try await settlePopover()
    }

    func escapePopover() async throws {
        #if os(Linux)
        XCTAssertEqual(qs_escape_popover(host.window), 1)
        #else
        let popup = try XCTUnwrap(window.childWindows?.last(where: { $0.isVisible }))
        let event = try XCTUnwrap(NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: popup.windowNumber, context: nil,
            characters: "\u{1b}", charactersIgnoringModifiers: "\u{1b}", isARepeat: false, keyCode: 53))
        // Exercise AppKit's standard Escape key binding in this in-process window.
        popup.interpretKeyEvents([event])
        #endif
        try await settlePopover()
    }

    func capturePopover(_ filename: String, directoryVariable: String) throws {
        #if os(Linux)
        try capture(filename, directoryVariable: directoryVariable)
        #else
        guard let dir = ProcessInfo.processInfo.environment[directoryVariable] else { return }
        let popup = try XCTUnwrap(window.childWindows?.last(where: { $0.isVisible }))
        let view = try XCTUnwrap(popup.contentView), frame = try XCTUnwrap(popoverFrame)
        let panel = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: panel)
        hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        panel.draw(in: CGRect(x: frame.minX, y: CGFloat(height) - frame.maxY, width: frame.width, height: frame.height))
        NSGraphicsContext.restoreGraphicsState()
        let url = URL(fileURLWithPath: dir).appendingPathComponent(filename)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: url)
        #endif
    }
}

@MainActor @Observable private final class Presentation {
    struct Item: Identifiable { var id: Int }
    var showing = false
    var item: Item?
    var presses: [Int] = []
    var presented: [Bool] = []
}

final class PopoverTests: XCTestCase {
    #if os(Linux)
    @MainActor func testX11PopoverOwnsItsBodyAndArrowAndLeavesCornersToTheParent() async throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["QTSWIFTUI_X11_POPOVER"] == "1" &&
                          ProcessInfo.processInfo.environment["QT_QPA_PLATFORM"] == "xcb" &&
                          FileManager.default.isExecutableFile(atPath: "/usr/bin/xdotool"))
        func pointerWindow(at point: CGPoint, scale: CGFloat) throws -> String {
            let process = Process(), result = Pipe()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/xdotool")
            process.arguments = ["mousemove", String(Int((point.x * scale).rounded())), String(Int((point.y * scale).rounded())), "getmouselocation", "--shell"]
            process.standardOutput = result
            try process.run()
            process.waitUntilExit()
            XCTAssertEqual(process.terminationStatus, 0)
            let fields = String(decoding: result.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self).split(separator: "\n")
            return String(try XCTUnwrap(fields.first { $0.hasPrefix("WINDOW=") }))
        }
        for edge in [Edge.bottom, .leading, .trailing, .top] {
            let model = Presentation()
            let anchor = Color.blue.frame(width: 60, height: 30)
                .popover(isPresented: Binding(get: { model.showing }, set: { model.showing = $0 }), arrowEdge: edge) {
                    Color.white.frame(width: 120, height: 70)
                }
            let screen = try await ScreenWindow(anchor, width: 480, height: 420, keyboard: true)
            defer { screen.close() }
            let window = qs_window_frame(screen.host.window)
            let scale = qs_window_scale(screen.host.window)
            let parent = try pointerWindow(at: CGPoint(x: window.x + 240, y: window.y + 210), scale: scale)
            model.showing = true
            try await screen.settlePopover()
            let popup = try XCTUnwrap(screen.popoverFrame).offsetBy(dx: window.x, dy: window.y)
            let body = try pointerWindow(at: CGPoint(x: popup.midX, y: popup.midY), scale: scale)
            XCTAssertNotEqual(body, parent)
            for x in [popup.minX + 1, popup.maxX - 2] {
                for y in [popup.minY + 1, popup.maxY - 2] {
                    XCTAssertEqual(try pointerWindow(at: CGPoint(x: x, y: y), scale: scale), parent)
                }
            }
            let tip: CGPoint = switch edge {
            case .bottom: CGPoint(x: popup.midX, y: popup.minY + 4)
            case .top: CGPoint(x: popup.midX, y: popup.maxY - 4)
            case .leading: CGPoint(x: popup.maxX - 4, y: popup.midY)
            case .trailing: CGPoint(x: popup.minX + 4, y: popup.midY)
            }
            XCTAssertEqual(try pointerWindow(at: tip, scale: scale), body)
        }
    }
    #endif

    @MainActor func testArrowEdgesAndEscapeBinding() async throws {
        struct Sample: View {
            @Bindable var model: Presentation
            let edge: Edge
            var body: some View {
                Color.blue.frame(width: 60, height: 30)
                    .popover(isPresented: $model.showing, arrowEdge: edge) {
                        Color.white.frame(width: 120, height: 70)
                    }
            }
        }
        for edge in [Edge.bottom, .leading, .trailing, .top] {
            let model = Presentation()
            let window = try await ScreenWindow(Sample(model: model, edge: edge), width: 480, height: 420, keyboard: true)
            defer { window.close() }
            model.showing = true
            try await window.settlePopover()
            let popup = try XCTUnwrap(window.popoverFrame)
            XCTAssertGreaterThanOrEqual(popup.width, 120)
            XCTAssertGreaterThanOrEqual(popup.height, 70)
            switch edge {
            case .bottom: XCTAssertEqual(popup.minY, 225, accuracy: 2)
            case .top: XCTAssertEqual(popup.maxY, 195, accuracy: 2)
            case .leading: XCTAssertEqual(popup.maxX, 210, accuracy: 2)
            case .trailing: XCTAssertEqual(popup.minX, 270, accuracy: 2)
            }
            try await window.escapePopover()
            XCTAssertFalse(model.showing)
            XCTAssertNil(window.popoverFrame)
        }
    }

    @MainActor func testChangingPresentedItemAndDismissingFromInside() async throws {
        struct Panel: View {
            var id: Int
            let model: Presentation
            @Environment(\.dismiss) var dismiss
            @Environment(\.isPresented) var isPresented
            var body: some View {
                Button {
                    model.presses.append(id)
                    model.presented.append(isPresented)
                    dismiss()
                } label: { Color.blue.frame(width: 120, height: 70) }.buttonStyle(.plain)
            }
        }
        struct Sample: View {
            @Bindable var model: Presentation
            var body: some View {
                Color.gray.frame(width: 80, height: 40)
                    .popover(item: $model.item, attachmentAnchor: .point(.bottomTrailing), arrowEdge: .bottom) {
                        Panel(id: $0.id, model: model).interactiveDismissDisabled()
                    }
            }
        }
        let model = Presentation()
        let window = try await ScreenWindow(Sample(model: model), width: 480, height: 420, keyboard: true)
        defer { window.close() }
        model.item = .init(id: 1)
        try await window.settlePopover()
        let first = try XCTUnwrap(window.popoverFrame)
        XCTAssertEqual(first.midX, 280, accuracy: 2)
        XCTAssertEqual(first.minY, 230, accuracy: 2)
        #if os(Linux)
        try await window.escapePopover()
        XCTAssertEqual(model.item?.id, 1)
        XCTAssertNotNil(window.popoverFrame)
        #endif
        model.item = .init(id: 2)
        try await window.settlePopover()
        let frame = try XCTUnwrap(window.popoverFrame)
        try await window.clickPopover(Int(frame.width / 2), Int(frame.height / 2))
        XCTAssertFalse(EnvironmentValues().isPresented)
        XCTAssertEqual(model.presses, [2])
        XCTAssertEqual(model.presented, [true])
        XCTAssertNil(model.item)
        XCTAssertNil(window.popoverFrame)
    }
}
