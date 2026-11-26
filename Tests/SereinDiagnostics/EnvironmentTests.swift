import SwiftUI
import XCTest

private struct EditorCallbacks {
    var submit: (() -> Void)?
}

private extension EnvironmentValues {
    @Entry var editorCallbacks = EditorCallbacks()
}

final class EnvironmentTests: XCTestCase {
    func testInferredEntryWithANonSendableDefault() {
        var environment = EnvironmentValues()
        var submitted = false
        environment.editorCallbacks.submit = { submitted = true }
        environment.editorCallbacks.submit?()
        XCTAssertTrue(submitted)
        XCTAssertNil(EnvironmentValues().editorCallbacks.submit)
    }

    @MainActor func testURLDispositionAndRegionalOverrides() async {
        let url = URL(string: "https://example.test/help")!
        var environment = EnvironmentValues()
        var seen: [URL] = []
        for expected in [true, false] {
            environment.openURL = OpenURLAction { destination in
                seen.append(destination)
                return expected ? .handled : .discarded
            }
            let accepted = await withCheckedContinuation { continuation in
                environment.openURL(url) { continuation.resume(returning: $0) }
            }
            XCTAssertEqual(accepted, expected)
        }
        XCTAssertEqual(seen, [url, url])
        environment.locale = Locale(identifier: "de_DE")
        environment.timeZone = TimeZone(secondsFromGMT: 3600)!
        environment.calendar = Calendar(identifier: .gregorian)
        let copy = environment
        environment.timeZone = .gmt
        XCTAssertEqual(copy.timeZone.secondsFromGMT(), 3600)
        XCTAssertEqual(copy.locale.identifier, "de_DE")
        XCTAssertEqual(copy.calendar.identifier, .gregorian)
    }
}
