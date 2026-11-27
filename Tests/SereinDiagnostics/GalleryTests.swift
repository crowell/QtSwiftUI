import XCTest
import SwiftUI
import SignalI18n
@testable import CallDiagnostics
#if os(Linux)
import QtBridge
@testable import SwiftUI
#else
import AppKit
#endif

@Observable private final class GallerySelection {
    var tab = MediaGalleryTab.media
    var order = MediaSortOrder.date
}

final class GalleryTests: XCTestCase {
    @MainActor func testProductionMediaTilesWrapCropAndRespond() async throws {
        let attachments = GalleryMediaSample.attachments
        XCTAssertEqual(attachments.count, 8)
        XCTAssertEqual(attachments.compactMap(\.image).count, 4)
        XCTAssertEqual(attachments.compactMap(\.blurHash).count, 4)
        for width in [400, 520, 640] {
            let panel = GalleryPreview(populated: true)
                .environment(\.axoAnimationsDisabled, true).environment(\.colorScheme, .light)
                .frame(width: CGFloat(width), height: 440)
            #if os(Linux)
            let host = Host(title: "Populated media gallery") { panel.resolve($0) }
            defer { host.close() }
            host.open(width: width, height: 440)
            func rgb(_ x: Int, _ y: Int) -> UInt32 { qs_pixel(host.window, Int32(x), Int32(y)) & 0xffffff }
            #else
            // The scroll view needs a live AppKit hierarchy for its contents to draw.
            let hosting = NSHostingView(rootView: panel)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: width, height: 440),
                                  styleMask: [.borderless], backing: .buffered, defer: false)
            window.contentView = hosting
            window.orderFrontRegardless()
            defer { window.orderOut(nil) }
            hosting.layoutSubtreeIfNeeded()
            try await Task.sleep(for: .milliseconds(50))
            let image = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: 440,
                                                       bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                                       isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
            hosting.cacheDisplay(in: hosting.bounds, to: image)
            if let dir = ProcessInfo.processInfo.environment["QTSWIFTUI_GALLERY_REFERENCE"] {
                let url = URL(fileURLWithPath: dir).appendingPathComponent("gallery-populated-\(width).png")
                try XCTUnwrap(image.representation(using: .png, properties: [:])).write(to: url)
            }
            func rgb(_ x: Int, _ y: Int) -> UInt32 {
                let color = image.colorAt(x: x, y: y)!.usingColorSpace(.sRGB)!
                return UInt32((color.redComponent * 255).rounded()) << 16 | UInt32((color.greenComponent * 255).rounded()) << 8 |
                       UInt32((color.blueComponent * 255).rounded())
            }
            #endif
            let columns = width < 495 ? 3 : width < 600 ? 4 : 5
            let side = min(120, (Double(width - 40) - Double(columns - 1) * 4) / Double(columns))
            let originY = 94
            for i in attachments.indices {
                let x = 20 + Int((Double(i % columns) * (side + 4)).rounded())
                let y = originY + Int((Double(i / columns) * (side + 4)).rounded())
                let points = [0.18, 0.35, 0.65, 0.82].flatMap { dx in
                    [0.18, 0.74].map { dy in rgb(x + Int(side * dx), y + Int(side * dy)) }
                }
                XCTAssertGreaterThan(Set(points).count, 4, "Tile \(i) at width \(width) contains the decoded pixels")
                if i % columns != columns - 1 {
                    XCTAssertEqual(rgb(x + Int(side.rounded()) + 1, y + 10), rgb(2, y + 10), "Gap after tile \(i)")
                }
            }
            #if os(Linux)
            let strings = Localizer(locale: "en")
            XCTAssertEqual(qs_click_named_button(host.window, strings("icu:startDownload")), 1)
            XCTAssertEqual(qs_click_named_button(host.window, strings("icu:cancelDownload")), 1)
            XCTAssertEqual(qs_click_named_button(host.window, strings("icu:imageOpenAlt")), 1)
            XCTAssertEqual(qs_read_text(host.window, nil, "Today"), 0)
            XCTAssertEqual(qs_click_named_button(host.window, strings("icu:close")), 1)
            XCTAssertEqual(qs_read_text(host.window, nil, "Today"), 1)
            XCTAssertEqual(qs_click_named_button(host.window, strings("icu:MediaGallery__sort")), 1)
            XCTAssertEqual(qs_click_point(host.window, Int32(width-100), 123), 1)
            XCTAssertEqual(qs_read_text(host.window, nil, "Today"), 0)
            XCTAssertEqual(qs_read_text(host.window, nil, "1 kB"), 1)
            #endif
        }
    }

    @MainActor func testProductionPanelHeaderAndEmptyState() async throws {
        let strings = Localizer(locale: "en")
        for width in [520, 1200] {
            let selection = GallerySelection()
            var backs = 0
            let panel = GalleryPanel(tab: Binding(get: { selection.tab }, set: { selection.tab = $0 }),
                                     order: Binding(get: { selection.order }, set: { selection.order = $0 }),
                                     onBack: { backs += 1 }).environment(\.axoAnimationsDisabled, true)
                .environment(\.colorScheme, .light).frame(width: CGFloat(width), height: 440)
            #if os(Linux)
            let host = Host(title: "All media") { panel.resolve($0) }
            defer { host.close() }
            host.open(width: width, height: 440)
            func dark(_ x: Int, _ y: Int) -> Bool { qs_pixel(host.window, Int32(x), Int32(y)) & 255 < 125 }
            #else
            let renderer = ImageRenderer(content: panel)
            let image = NSBitmapImageRep(cgImage: try XCTUnwrap(renderer.cgImage))
            if let dir = ProcessInfo.processInfo.environment["QTSWIFTUI_GALLERY_REFERENCE"] {
                let url = URL(fileURLWithPath: dir).appendingPathComponent("gallery-\(width).png")
                try XCTUnwrap(image.representation(using: .png, properties: [:])).write(to: url)
            }
            func dark(_ x: Int, _ y: Int) -> Bool { image.colorAt(x: x, y: y)!.blueComponent < 0.49 }
            #endif
            // Each tab gets 80 points after the two spacers share the remaining width.
            for offset in [-120, -40, 40, 120] {
                let center = width / 2 + offset
                let ink = (center-22..<center+22).filter { x in (19..<34).contains { dark(x, $0) } }
                XCTAssertGreaterThan(ink.count, 20, "Full tab label at \(center)")
            }
            for range in [20..<45, (width - 45)..<(width - 20)] {
                XCTAssertTrue(range.contains { x in (14..<38).contains { dark(x, $0) } }, "Header icon at \(range)")
            }
            XCTAssertTrue((width/2-50..<width/2+50).contains { x in (226..<250).contains { dark(x, $0) } })
            #if os(Linux)
            for (offset, selected): (Int, MediaGalleryTab) in [(40, .links), (120, .documents), (-120, .media), (-40, .audio)] {
                XCTAssertEqual(qs_click_point(host.window, Int32(width / 2 + offset), 26), 1)
                XCTAssertEqual(selection.tab, selected)
                XCTAssertEqual(qs_read_text(host.window, nil, strings(MediaGalleryEmptyState(tab: selected).strings.0)), 1)
            }
            XCTAssertEqual(qs_click_named_button(host.window, strings("icu:MediaGallery__sort")), 1)
            XCTAssertEqual(qs_read_text(host.window, nil, strings("icu:MediaGallery__sort--header")), 1)
            func checkmark(at y: Int) -> Bool {
                qs_dark_ink(host.window, Int32(width-195), Int32(y-5), 14, 11) != 0
            }
            let dateLabel = strings("icu:MediaGallery__sort__date")
            let sizeLabel = strings("icu:MediaGallery__sort__size")
            XCTAssertEqual(qs_accessible_checked(host.window, dateLabel), 1)
            XCTAssertEqual(qs_accessible_checked(host.window, sizeLabel), 0)
            XCTAssertTrue(checkmark(at: 96))
            XCTAssertFalse(checkmark(at: 126))
            XCTAssertEqual(qs_click_point(host.window, Int32(width-100), 123), 1)
            XCTAssertEqual(selection.order, .size)
            // Observation invalidates through Swift's main executor before Qt lays out the next frame.
            for _ in 0..<30 {
                if checkmark(at: 126) { break }
                try await Task.sleep(for: .milliseconds(10))
                qs_flush()
            }
            XCTAssertFalse(checkmark(at: 96))
            XCTAssertTrue(checkmark(at: 126))
            XCTAssertEqual(qs_accessible_checked(host.window, dateLabel), 0)
            XCTAssertEqual(qs_accessible_checked(host.window, sizeLabel), 1)
            if width == 520, let path = ProcessInfo.processInfo.environment["QTSWIFTUI_GALLERY_MENU_CAPTURE"] {
                XCTAssertEqual(qs_capture(host.window, path), 1)
            }
            XCTAssertEqual(qs_click_point(host.window, 150, 200), 1)
            XCTAssertEqual(qs_read_text(host.window, nil, strings("icu:MediaGallery__sort--header")), 0)
            XCTAssertEqual(qs_accessible_element(host.window, strings("icu:MediaGallery__sort"), -1, "Press"), 1)
            XCTAssertEqual(qs_accessible_element(host.window, strings("icu:MediaGallery__sort__date"), 0, "Toggle"), 1)
            XCTAssertEqual(selection.order, .date)
            XCTAssertEqual(qs_click_point(host.window, 150, 200), 1)
            XCTAssertEqual(qs_click_named_button(host.window, strings("icu:goBack")), 1)
            XCTAssertEqual(backs, 1)
            #endif
        }
    }
}
