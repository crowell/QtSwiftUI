import XCTest
import SwiftUI
@testable import CallDiagnostics

final class ContactFlowTests: XCTestCase {
    @MainActor func testContactScreens() async throws {
        for (screen, height, filename) in [(ContactScreen.about, 620, "about-contact.png"), (.note, 380, "note-preview.png")] {
            let window = try await ScreenWindow(ContactFlowPreview(model: .init(start: screen)), width: 520, height: height)
            try window.capture(filename, directoryVariable: "QTSWIFTUI_CONTACT_REFERENCE")
            window.close()
        }
        var destinations: [String] = []
        let about = try await ScreenWindow(AppAboutPreview()
            .environment(\.openURL, OpenURLAction { destinations.append($0.absoluteString); return .handled }),
            width: 520, height: 440)
        defer { about.close() }
        try about.capture("about.png", directoryVariable: "QTSWIFTUI_CONTACT_REFERENCE")
        try await about.click(252, 309)
        try await about.click(252, 349)
        try await about.click(252, 368)
        XCTAssertEqual(destinations, ["https://signal.org", "https://github.com/signalapp/Signal-Desktop/blob/main/ACKNOWLEDGMENTS.md", "https://signal.org/legal"])
    }

    @MainActor func testAdmissionOpensContactAndEditsNote() async throws {
        let model = ContactFlow(start: .request)
        var urls: [String] = []
        let screen = ContactFlowPreview(model: model)
            .environment(\.openURL, OpenURLAction { urls.append($0.absoluteString); return .handled })
        let window = try await ScreenWindow(screen, width: 520, height: 620)
        defer { window.close() }

        try await window.click(215, 278)
        XCTAssertEqual(model.screen, .about)
        try await window.click(225, 504)
        XCTAssertEqual(model.screen, .note)
        try await window.click(168, 319)
        XCTAssertEqual(urls, ["https://example.org/weekend"])
        try await window.click(312, 354)
        XCTAssertEqual(model.screen, .edit)
        try window.capture("contact-editor.png", directoryVariable: "QTSWIFTUI_CONTACT_REFERENCE")
        try await window.click(238, 410)
        try await window.type(" after lunch")
        try await window.click(380, 478)
        XCTAssertEqual(model.screen, .note)
        XCTAssertTrue(model.details.note?.contains("after lunch") == true, "\(model.details)")
        let saved = model.details
        try await window.click(312, 354)
        try await window.click(238, 410)
        try await window.type(" discard")
        try await window.click(301, 478)
        XCTAssertEqual(model.details, saved)
        XCTAssertEqual(model.screen, .note)
        try await window.click(377, 354)
        XCTAssertEqual(model.screen, .about)
        try await window.click(389, 119)
        XCTAssertEqual(model.screen, .request)
    }
}
