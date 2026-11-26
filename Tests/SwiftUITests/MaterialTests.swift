import QtBridge
import XCTest
@testable import SwiftUI

final class MaterialTests: XCTestCase {
    @MainActor func testCanvasMaterialSamplesEarlierDrawings() async {
        let host = Host(title: "Canvas material") { context in
            Canvas { graphics, size in
                graphics.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.black))
                graphics.fill(Path(CGRect(x: 50, y: 0, width: 50, height: 40)), with: .color(.white))
                graphics.fill(Path(CGRect(x: 10, y: 5, width: 80, height: 30)), with: .style(.thinMaterial))
            }.resolve(context)
        }
        defer { host.close() }
        host.open(width: 100, height: 40)
        qs_flush()
        let left = qs_pixel(host.window, 22, 20) & 255, right = qs_pixel(host.window, 78, 20) & 255
        XCTAssertGreaterThan(left, 5)
        XCTAssertLessThan(left, right)
        XCTAssertEqual(qs_pixel(host.window, 4, 20) & 255, 0)
    }

    @MainActor func testClippedBackdropChangesWithContentBehindIt() async {
        var reversed = false, dark = false
        let host = Host(title: "Material") { context in
            ZStack {
                HStack(spacing: 0) {
                    (reversed ? Color.white : Color.black)
                    (reversed ? Color.black : Color.white)
                }
                Rectangle().fill(.thinMaterial).frame(width: 100, height: 40)
                Color.red.frame(width: 6, height: 6)
            }.environment(\.colorScheme, dark ? .dark : .light).resolve(context)
        }
        defer { host.close() }
        host.open(width: 140, height: 60)
        func sample(_ x: Int32, _ y: Int32 = 23) -> Int { Int(qs_pixel(host.window, x, y) & 255) }
        func update() { host.update(); qs_flush() }
        update()
        XCTAssertEqual(sample(8), 0)
        XCTAssertEqual(sample(131), 255)
        XCTAssertGreaterThan(sample(35), 5)
        XCTAssertLessThan(sample(35), sample(68))
        XCTAssertLessThan(sample(68), sample(74))
        XCTAssertLessThan(sample(74), sample(108))
        XCTAssertEqual(qs_pixel(host.window, 70, 30) & 0xffffff, 0xff3b30)
        reversed = true
        update()
        let light = sample(35)
        XCTAssertGreaterThan(light, sample(108))
        dark = true
        update()
        XCTAssertLessThan(sample(35), light)
    }
}
