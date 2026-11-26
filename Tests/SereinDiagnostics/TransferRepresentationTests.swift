import CoreTransferable
import Foundation
import SwiftUI
import UniformTypeIdentifiers
import XCTest

private struct MarkedText: Equatable, Transferable {
    let text: String
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation<MarkedText>(contentType: .utf8PlainText, exporting: { Data($0.text.utf8) },
                                       importing: { MarkedText(text: String(decoding: $0, as: UTF8.self)) })
        DataRepresentation<MarkedText>(importedContentType: .html) { data in
            MarkedText(text: "html/" + String(decoding: data, as: UTF8.self))
        }
    }
}

final class TransferRepresentationTests: XCTestCase {
    @MainActor func testDataRepresentationOrderAndDesktopRoundTrips() async throws {
        XCTAssertEqual(String.importedContentTypes(), [.utf8PlainText])
        XCTAssertEqual(Data.importedContentTypes(), [.data])
        XCTAssertEqual(URL.importedContentTypes(), [.url, .fileURL])
        XCTAssertEqual(MarkedText.importedContentTypes(), [.utf8PlainText, .html])
        let message = MarkedText(text: "Fähre")
        let data = try await message.exported(as: .utf8PlainText)
        XCTAssertEqual(data, Data(message.text.utf8))
        let plain = try await MarkedText(importing: data, contentType: .utf8PlainText)
        let html = try await MarkedText(importing: data, contentType: .html)
        XCTAssertEqual(plain, message)
        XCTAssertEqual(html.text, "html/Fähre")
        let link = try XCTUnwrap(URL(string: "https://example.org/Blue%20sky"))
        let urlData = try await link.exported(as: .url)
        XCTAssertEqual(urlData, Data(link.absoluteString.utf8))
        let decoded = try await URL(importing: urlData, contentType: .url)
        XCTAssertEqual(link, decoded)
    }
}
