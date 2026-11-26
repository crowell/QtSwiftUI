import QtBridge
import XCTest
@testable import SwiftUI

final class TransferTests: XCTestCase {
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
