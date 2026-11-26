import QtBridge
import XCTest
@testable import SwiftUI

final class ClipboardCommandTests: XCTestCase {
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
        qs_clipboard_text("External clipboard")
        key("Ctrl+V")
        received.first?.loadDataRepresentation(forTypeIdentifier: UTType.text.identifier) { data, _ in
            XCTAssertEqual(data, Data("External clipboard".utf8))
        }
    }
}
