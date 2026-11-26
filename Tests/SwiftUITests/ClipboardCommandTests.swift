import QtBridge
import XCTest
@testable @_spi(Qt) import SwiftUI

final class ClipboardCommandTests: XCTestCase {
    @MainActor func testPasteDestinationFiltersItemsFromKeyboardAndEditMenu() async throws {
        var batches: [[String]] = []
        var validations = 0
        let host = Host(title: "Paste destination") { context in
            VStack {
                Button("Copy values") {}.onCopyCommand {
                    ["first", "skip", "last"].map { NSItemProvider(object: $0 as NSString) }
                }
                Button("Destination") {}
                    .pasteDestination(for: String.self) { batches.append($0) } validator: { values in
                        validations += 1
                        return values.filter { $0 != "skip" }
                    }
            }.resolve(context)
        }
        defer { host.close() }
        host.open(width: 180, height: 100)
        _ = qs_click_point(host.window, 90, 34)
        XCTAssertTrue(QtDesktop.perform(.copy))
        _ = qs_click_point(host.window, 90, 66)
        XCTAssertTrue(QtDesktop.perform(.paste))
        for _ in 0..<30 where validations < 1 { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(batches, [["first", "last"]])

        QtDesktop.copy("skip")
        _ = qs_send_key_sequence(host.window, "Ctrl+V")
        for _ in 0..<30 where validations < 2 { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(validations, 2)
        XCTAssertEqual(batches.count, 1)

        // The paste scope belongs to the second control only.
        _ = qs_click_point(host.window, 90, 34)
        XCTAssertFalse(QtDesktop.perform(.paste))
    }

    @MainActor func testComposerAcceptsCopiedFileURLs() async {
        let path = URL(fileURLWithPath: "/tmp/A picture.png")
        var received: [NSItemProvider] = []
        let host = Host(title: "Clipboard files") { context in
            VStack {
                Button("Copy file") {}.onCopyCommand { [NSItemProvider(object: path as NSURL)] }
                Button("Paste attachment") {}.onPasteCommand(of: [.fileURL]) { received = $0 }
            }.resolve(context)
        }
        defer { host.close() }
        host.open(width: 180, height: 100)
        _ = qs_click_point(host.window, 90, 34)
        _ = qs_send_key_sequence(host.window, "Ctrl+C")
        _ = qs_click_point(host.window, 90, 66)
        _ = qs_send_key_sequence(host.window, "Ctrl+V")
        XCTAssertEqual(received.count, 1)
        received.first?.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, error in
            XCTAssertNil(error)
            XCTAssertEqual(data, Data((path.absoluteString + "\r\n").utf8))
        }
    }
    @MainActor func testFocusedCutCopyAndValidatedPaste() async {
        var copies = 0, cuts = 0, received: [NSItemProvider] = []
        var validate = true
        let host = Host(title: "Clipboard") { context in
            VStack {
                Button("Copy target") {}
                    .onCopyCommand {
                        copies += 1
                        return ["first", "Færge"].map { NSItemProvider(object: $0 as NSString) }
                    }
                    .onCutCommand {
                        cuts += 1
                        return [NSItemProvider(object: "cut" as NSString)]
                    }
                Button("Paste target") {}
                    .onPasteCommand(of: [.text], validator: { validate ? $0 : nil }) { received = $0 }
            }.resolve(context)
        }
        defer { host.close() }
        host.open(width: 180, height: 100)
        func key(_ sequence: String) { _ = qs_send_key_sequence(host.window, sequence); qs_flush() }
        _ = qs_click_point(host.window, 90, 34)
        key("Ctrl+C")
        XCTAssertEqual(copies, 1)
        _ = qs_click_point(host.window, 90, 66)
        key("Ctrl+V")
        XCTAssertEqual(received.count, 2)
        received.last?.loadDataRepresentation(forTypeIdentifier: UTType.text.identifier) { data, error in
            XCTAssertNil(error)
            XCTAssertEqual(data, Data("Færge".utf8))
        }
        received = []
        validate = false
        key("Ctrl+V")
        XCTAssertTrue(received.isEmpty)
        validate = true
        _ = qs_click_point(host.window, 90, 34)
        key("Ctrl+X")
        XCTAssertEqual(cuts, 1)
        _ = qs_click_point(host.window, 90, 66)
        key("Ctrl+V")
        XCTAssertEqual(received.count, 1)
        QtDesktop.copy("External clipboard")
        key("Ctrl+V")
        received.first?.loadDataRepresentation(forTypeIdentifier: UTType.text.identifier) { data, _ in
            XCTAssertEqual(data, Data("External clipboard".utf8))
        }
    }
}
