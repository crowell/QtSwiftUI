import QtBridge
import XCTest
@_spi(Qt) @testable import SwiftUI

final class PasteButtonTests: XCTestCase {
    @MainActor func testValidatesPreferredTypeAndRechecksChangedPasteboard() async {
        var result = ""
        var reject = false
        let host = Host(title: "Paste") { context in
            VStack {
                Button("Copy items") {}.onCopyCommand {
                    [NSItemProvider(object: "caption" as NSString),
                     NSItemProvider(object: URL(fileURLWithPath: "/tmp/notes.txt") as NSURL)]
                }
                PasteButton(supportedContentTypes: [.fileURL, .text], validator: { providers -> String? in
                    guard !reject, let item = providers.first else { return nil }
                    return item.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) ? "file" : "text"
                }, payloadAction: { result = $0 }).accessibilityIdentifier("paste")
                PasteButton(supportedTypes: [UTType.image.identifier]) { _ in XCTFail("Unexpected image") }
                    .accessibilityIdentifier("image")
            }.resolve(context)
        }
        defer { host.close() }
        host.open(width: 180, height: 150)
        _ = qs_click_point(host.window, 90, 44)
        _ = qs_send_key_sequence(host.window, "Ctrl+C")
        host.update()
        qs_flush()
        XCTAssertEqual(qs_click(host.window, "paste"), 1)
        XCTAssertEqual(result, "file")
        XCTAssertEqual(qs_click(host.window, "image"), 0)
        QtDesktop.copy("new contents")
        XCTAssertEqual(qs_click(host.window, "paste"), 1)
        XCTAssertEqual(result, "text")
        reject = true
        host.update()
        qs_flush()
        XCTAssertEqual(qs_click(host.window, "paste"), 0)
    }
}
