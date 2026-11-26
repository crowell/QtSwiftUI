import QtBridge
import XCTest
@testable import SwiftUI

final class TransferTests: XCTestCase {
    @MainActor func testURLDropPreservesURIListOrderAndLocation() async {
        var payload = "# screen capture\r\nfile:///tmp/Blue%20sky.png\r\nhttps://example.org/ferry\r\n"
        var points: [CGPoint] = [], targeting: [Bool] = [], received: [URL] = []
        let host = Host(title: "URL drop") { context in
            HStack(spacing: 0) {
                Color.blue.onDrag { NSItemProvider(item: payload as NSString, typeIdentifier: UTType.url.identifier) }
                Color.green.dropDestination(for: URL.self) { urls, point in
                    points.append(point)
                    received = urls
                    return urls.count == 2
                } isTargeted: { targeting.append($0) }
            }.resolve(context)
        }
        defer { host.close() }
        host.open(width: 120, height: 40)
        XCTAssertEqual(qs_transfer_between(host.window, 10, 10, 72, 13), 1)
        XCTAssertEqual(points, [CGPoint(x: 12, y: 13)])
        XCTAssertEqual(targeting, [true, false])
        XCTAssertEqual(received.map(\.absoluteString), ["file:///tmp/Blue%20sky.png", "https://example.org/ferry"])
        payload = "file:///tmp/One.png"
        XCTAssertEqual(qs_transfer_between(host.window, 10, 10, 72, 13), 0)
        payload = "# no URLs\r\nrelative/path"
        XCTAssertEqual(qs_transfer_between(host.window, 10, 10, 72, 13), 0)
        XCTAssertEqual(points.count, 2)
    }

    @MainActor func testTypedDropUsesNativeMimeDataAndLocalCoordinates() async {
        var produced = 0, points: [CGPoint] = [], targeting: [Bool] = [], accepts = true
        let targeted = Binding(get: { targeting.last ?? false }, set: { targeting.append($0) })
        var received: NSItemProvider?
        let host = Host(title: "Transfer") { context in
            HStack(spacing: 0) {
                Color.blue.onDrag {
                    produced += 1
                    return NSItemProvider(object: "Færge 🛳" as NSString)
                }
                Color.green.onDrop(of: [.text], isTargeted: targeted) { items, location in
                    received = items.first
                    points.append(location)
                    return accepts
                }
                Color.red.onDrop(of: [.image], isTargeted: nil) { _ in
                    XCTFail("A text drag entered the image destination")
                    return true
                }
            }.resolve(context)
        }
        defer { host.close() }
        host.open(width: 150, height: 40)
        XCTAssertEqual(produced, 0)
        XCTAssertEqual(qs_transfer_between(host.window, 13, 16, 70, 23), 1)
        XCTAssertEqual(points, [CGPoint(x: 20, y: 23)])
        XCTAssertEqual(targeting, [true, false])
        XCTAssertTrue(received?.hasItemConformingToTypeIdentifier(UTType.text.identifier) == true)
        received?.loadDataRepresentation(forTypeIdentifier: UTType.plainText.identifier) { data, error in
            XCTAssertNil(error)
            XCTAssertEqual(data, Data("Færge 🛳".utf8))
        }
        accepts = false
        XCTAssertEqual(qs_transfer_between(host.window, 13, 16, 65, 12), 0)
        XCTAssertEqual(qs_transfer_between(host.window, 13, 16, 120, 16), 0)
        XCTAssertEqual(points.count, 2)
        XCTAssertEqual(produced, 3)
    }
}
