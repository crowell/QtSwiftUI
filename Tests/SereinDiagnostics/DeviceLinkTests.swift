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

final class DeviceLinkTests: XCTestCase {
    @MainActor func testDeviceLinkScreens() async throws {
        let en = Localizer(locale: "en")
        for showError in [true, false] {
            let content = DeviceLinkPreview(showError: showError)
                .environment(\.axoAnimationsDisabled, true)
                .environment(\.i18n, en)
                .environment(\.colorScheme, .light)
                .frame(width: 680, height: 420)
            #if os(Linux)
            let host = Host(title: "Device link") { content.resolve($0) }
            host.open(width: 680, height: 420)
            defer { host.close() }
            func rgb(_ x: Int, _ y: Int) -> (Int, Int, Int) {
                let p = qs_pixel(host.window, Int32(x), Int32(y))
                return (Int(p >> 16 & 255), Int(p >> 8 & 255), Int(p & 255))
            }
            #else
            let bitmap = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 680, pixelsHigh: 420,
                                                       bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                                       isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
            let graphics = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: bitmap))
            ImageRenderer(content: content).render { _, draw in draw(graphics.cgContext) }
            if let directory = ProcessInfo.processInfo.environment["QTSWIFTUI_LINK_REFERENCE"] {
                let url = URL(fileURLWithPath: directory).appendingPathComponent(showError ? "link-error.png" : "link-device.png")
                try XCTUnwrap(bitmap.representation(using: .png, properties: [:])).write(to: url)
            }
            func rgb(_ x: Int, _ y: Int) -> (Int, Int, Int) {
                let c = bitmap.colorAt(x: x, y: y)!.usingColorSpace(.sRGB)!
                return (Int(c.redComponent * 255), Int(c.greenComponent * 255), Int(c.blueComponent * 255))
            }
            #endif
            let logo = rgb(48, 51)
            XCTAssertGreaterThan(logo.2, logo.0 + 80)
            XCTAssertGreaterThan(rgb(2, 2).0, 230)
            if showError {
                let fill = rgb(303, 246)
                XCTAssertGreaterThan(fill.2, fill.0 + 80)
                #if os(Linux)
                XCTAssertEqual(qs_read_text(host.window, nil, en("icu:installConnectionFailed")), 1)
                XCTAssertEqual(qs_click_named_button(host.window, en("icu:installTryAgain")), 1)
                #endif
            } else {
                let arc = rgb(364, 178)
                XCTAssertLessThan(arc.0, 185)
            }
            #if os(Linux)
            let combined = en("icu:initialSync") + ", " + en("icu:initialSync__subtitle")
            XCTAssertEqual(qs_accessible_element(host.window, combined, 0, nil), 1)
            XCTAssertEqual(qs_read_text(host.window, nil, en("icu:initialSync")), 1)
            #endif
        }
    }

    #if os(Linux)
    @MainActor func testProgressSpinnerRotatesWhileTheViewGraphIsIdle() async {
        var renders = 0
        let screen = InstallScreenLinkInProgressStep()
        let host = Host(title: "Syncing") { context in
            renders += 1
            return screen.resolve(context)
        }
        host.open(width: 680, height: 420)
        defer { host.close() }
        qs_flush()
        let start = renders
        let initial = qs_pixel(host.window, 364, 178)
        var advanced = false
        for _ in 0..<24 {
            try? await Task.sleep(for: .milliseconds(25))
            qs_flush()
            if qs_pixel(host.window, 364, 178) != initial { advanced = true; break }
        }
        XCTAssertTrue(advanced)
        XCTAssertEqual(renders, start)
    }

    @MainActor func testOriginalErrorActionsAndExternalURLs() async {
        let en = Localizer(locale: "en")
        for error in InstallScreenError.allCases {
            var retries = 0, quits = 0, urls: [URL] = []
            let screen = InstallScreenErrorStep(error: error, quit: { quits += 1 }, tryAgain: { retries += 1 })
                .environment(\.openURL, OpenURLAction { urls.append($0); return .handled })
                .environment(\.i18n, en)
            let host = Host(title: "Link error") { screen.resolve($0) }
            host.open(width: 680, height: 420)
            defer { host.close() }
            switch error {
            case .tooManyDevices, .connectionFailed:
                XCTAssertEqual(qs_click_named_button(host.window, en("icu:installTryAgain")), 1)
                XCTAssertEqual(retries, 1)
            case .tooOld, .qrCodeFailed:
                let old = error == .tooOld
                XCTAssertEqual(qs_click_named_button(host.window, en(old ? "icu:upgrade" : "icu:Install__learn-more")), 1)
                XCTAssertEqual(urls, [old ? InstallScreenErrorStep.downloadURL : InstallScreenErrorStep.desktopSupportURL])
                XCTAssertEqual(qs_click_named_button(host.window, en("icu:quit")), 1)
                XCTAssertEqual(quits, 1)
            }
        }
    }
    #endif
}
