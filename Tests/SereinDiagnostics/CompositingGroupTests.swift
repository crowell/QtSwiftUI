import SwiftUI
import XCTest
@testable import CallDiagnostics

final class CompositingGroupTests: XCTestCase {
    @MainActor func testGroupOpacityTreatsOverlappingBlackShapesAsOne() async throws {
        let control = ZStack {
            Color.white
            ZStack {
                Rectangle().fill(.black).frame(width: 64, height: 24)
                Rectangle().fill(.black).frame(width: 24, height: 64)
            }.compositingGroup().opacity(0.5)
        }
        let window = try await ScreenWindow(control, width: 96, height: 96)
        defer { window.close() }
        XCTAssertEqual(window.pixel(48, 48), window.pixel(27, 48))
        let gray = window.pixel(48, 48) & 255
        XCTAssertGreaterThan(gray, 95)
        XCTAssertLessThan(gray, 200)
        XCTAssertEqual(window.pixel(8, 8) & 255, 255)
    }
}
