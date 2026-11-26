import QtBridge
import XCTest
@_spi(Qt) @testable import SwiftUI

private struct DesktopCaption: Transferable, Equatable {
    let text: String
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation<DesktopCaption>(importedContentType: .utf8PlainText) { bytes in
            guard let text = String(data: bytes, encoding: .utf8), text.hasPrefix("title: ") else {
                throw CocoaError(.fileReadCorruptFile)
            }
            return DesktopCaption(text: String(text.dropFirst(7)))
        }
    }
}

final class PasteButtonTests: XCTestCase {
    @MainActor func testTypedPasteDecodesCustomAndStandardPayloads() async throws {
        var text: [String] = [], titles: [DesktopCaption] = [], links: [URL] = []
        let host = Host(title: "Typed paste") { context in
            VStack {
                Button("Copy links") {}.onCopyCommand {
                    [NSItemProvider(item: "file:///tmp/a%20file\r\nhttps://example.org/b" as NSString,
                                    typeIdentifier: UTType.url.identifier)]
                }
                PasteButton(payloadType: String.self) { text = $0 }.accessibilityIdentifier("text")
                PasteButton(payloadType: DesktopCaption.self) { titles = $0 }.accessibilityIdentifier("caption")
                PasteButton(payloadType: URL.self) { links = $0 }.accessibilityIdentifier("links")
            }.resolve(context)
        }
        defer { host.close() }
        host.open(width: 220, height: 180)
        QtDesktop.copy("title: Fähre")
        host.update()
        qs_flush()
        XCTAssertEqual(qs_click(host.window, "text"), 1)
        XCTAssertEqual(qs_click(host.window, "caption"), 1)
        for _ in 0..<30 where titles.isEmpty || text.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(text, ["title: Fähre"])
        XCTAssertEqual(titles, [DesktopCaption(text: "Fähre")])
        _ = qs_click_point(host.window, 110, 45)
        _ = qs_send_key_sequence(host.window, "Ctrl+C")
        host.update()
        qs_flush()
        XCTAssertEqual(qs_click(host.window, "links"), 1)
        for _ in 0..<30 where links.isEmpty { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(links.map(\.absoluteString), ["file:///tmp/a%20file", "https://example.org/b"])
    }

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
