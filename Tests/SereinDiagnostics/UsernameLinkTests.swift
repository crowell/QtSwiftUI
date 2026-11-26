import ImagePNG
import SwiftUI
import XCTest
@testable import CallDiagnostics

final class UsernameLinkTests: XCTestCase {
    @MainActor func testCopyChooseCancelAndExportSelectedColor() async throws {
        let model = UsernameLinkModel()
        var copies: [String] = []
        model.copy = { copies.append($0) }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        defer { try? FileManager.default.removeItem(at: file) }
        model.saveDestination = { name in
            XCTAssertEqual(name, "alice.42.png")
            return file
        }

        let window = try await ScreenWindow(UsernameLinkPreview(model: model), width: 520, height: 540)
        defer { window.close() }
        try window.capture("username-link.png", directoryVariable: "QTSWIFTUI_USERNAME_REFERENCE")
        try await window.click(250, 200)
        try await window.click(44, 344)
        XCTAssertEqual(copies, [UsernameCardPreview.username, UsernameCardPreview.link])
        try await window.click(300, 273)
        try await window.click(362, 348)
        try window.capture("username-link-color.png", directoryVariable: "QTSWIFTUI_USERNAME_REFERENCE")
        XCTAssertEqual(window.pixel(174, 44), 0xa183d4)
        XCTAssertEqual(model.color, .blue)
        try await window.click(384, 431)
        XCTAssertEqual(window.pixel(174, 44), 0x506ecd)
        XCTAssertEqual(model.color, .blue)

        try await window.click(300, 273)
        try await window.click(362, 348)
        try await window.click(461, 431)
        XCTAssertEqual(model.color, .purple)
        try await window.click(222, 273)
        let data = try Data(contentsOf: file)
        let png = try PNGDecoder.decode([UInt8](data)).stillImage
        XCTAssertEqual(png.width, 1272)
        XCTAssertEqual(png.height, 1728)
        let color = png.pixel(x: 74 * 3, y: 230 * 3)
        XCTAssertEqual([color.r, color.g, color.b], [161, 131, 212])
    }

    @MainActor func testResetRequiresConfirmation() async throws {
        let model = UsernameLinkModel()
        let window = try await ScreenWindow(UsernameLinkPreview(model: model), width: 520, height: 540, keyboard: true)
        defer { window.close() }
        let background = window.pixel(5, 5)
        try await window.click(260, 437)
        XCTAssertNotEqual(window.pixel(5, 5), background)
        try window.capture("username-link-reset.png", directoryVariable: "QTSWIFTUI_USERNAME_REFERENCE")
        XCTAssertEqual(model.link, UsernameCardPreview.link)
        try await window.click(194, 305)
        XCTAssertEqual(window.pixel(5, 5), background)
        XCTAssertEqual(model.link, UsernameCardPreview.link)
        try await window.click(260, 437)
        XCTAssertNotEqual(window.pixel(5, 5), background)
        try await window.click(325, 305)
        try await window.settle()
        XCTAssertNotEqual(model.link, UsernameCardPreview.link)
        XCTAssertTrue(model.link.hasPrefix("https://signal.me/#eu/"))
    }
}
