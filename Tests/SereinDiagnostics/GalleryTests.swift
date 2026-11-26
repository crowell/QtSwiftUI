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
            for (key, selected) in [("icu:MediaGallery__tab__links", MediaGalleryTab.links),
                                    ("icu:MediaGallery__tab__files", .documents), ("icu:media", .media),
                                    ("icu:MediaGallery__tab__audio", .audio)] {
                XCTAssertEqual(qs_click_named_button(host.window, strings(key)), 1)
                XCTAssertEqual(selection.tab, selected)
                XCTAssertEqual(qs_read_text(host.window, nil, strings(MediaGalleryEmptyState(tab: selected).strings.0)), 1)
            }
            XCTAssertEqual(qs_click_named_button(host.window, strings("icu:MediaGallery__sort")), 1)
            XCTAssertEqual(qs_read_text(host.window, nil, strings("icu:MediaGallery__sort--header")), 1)
            func checkmark(at y: Int) -> Bool {
                qs_dark_ink(host.window, Int32(width-195), Int32(y-5), 14, 11) != 0
            }
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
            if width == 520, let path = ProcessInfo.processInfo.environment["QTSWIFTUI_GALLERY_MENU_CAPTURE"] {
                XCTAssertEqual(qs_capture(host.window, path), 1)
            }
            XCTAssertEqual(qs_click_point(host.window, 150, 200), 1)
            XCTAssertEqual(qs_read_text(host.window, nil, strings("icu:MediaGallery__sort--header")), 0)
            XCTAssertEqual(qs_click_named_button(host.window, strings("icu:goBack")), 1)
            XCTAssertEqual(backs, 1)
            #endif
        }
    }
}
