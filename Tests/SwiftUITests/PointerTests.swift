import QtBridge
import XCTest
@testable import SwiftUI

final class PointerTests: XCTestCase {
    func testHoverAndHelpReachQt() async {
        await MainActor.run {
            var events: [Bool] = []
            let host = Host(title: "Hover") { ctx in
                Text("Details").onHover { events.append($0) }
                    .help(Text("Show diagnostics")).accessibilityIdentifier("info").resolve(ctx)
            }
            defer { host.close() }
            host.open(width: 100, height: 48)
            events.removeAll()
            XCTAssertEqual(qs_hover(host.window, "info", 1), 1)
            XCTAssertEqual(qs_hover(host.window, "info", 0), 1)
            XCTAssertEqual(events, [true, false])
            XCTAssertEqual(qs_has_help(host.window, "info", "Show diagnostics"), 1)
        }
    }

    func testOpacityCompositesOverlappingChildrenOnce() async {
        await MainActor.run {
            let host = Host(title: "Opacity") { ctx in
                ZStack {
                    Color.white
                    ZStack {
                        Rectangle().fill(.black)
                        Rectangle().fill(.black).frame(width: 12, height: 12)
                    }
                    .opacity(0.5)
                }.resolve(ctx)
            }
            defer { host.close() }
            host.open(width: 40, height: 40)
            let single = qs_pixel(host.window, 4, 4) & 255
            let overlap = qs_pixel(host.window, 20, 20) & 255
            XCTAssertEqual(single, overlap)
            XCTAssertEqual(Double(single), 128, accuracy: 1)
        }
    }
}
