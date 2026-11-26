import QtBridge
import XCTest
@testable import SwiftUI

final class LinkTests: XCTestCase {
    @MainActor func testCustomLinkRouting() async {
        let input = URL(string: "https://example.test/help")!
        let replacement = URL(string: "https://example.test/local-help")!
        var dispatched: [URL] = []
        var accepted: [Bool] = []
        for result: OpenURLAction.Result in [.handled, .discarded, .systemAction, .systemAction(replacement)] {
            let action = OpenURLAction(handler: { _ in result }, systemOpen: {
                dispatched.append($0)
                return $0 == replacement
            })
            action(input) { accepted.append($0) }
        }
        XCTAssertEqual(accepted, [true, false, false, true])
        XCTAssertEqual(dispatched, [input, replacement])
        var clicked: [URL] = []
        let host = Host(title: "Links") { ctx in
            Link("Help", destination: input)
                .environment(\.openURL, OpenURLAction { clicked.append($0); return .handled })
                .accessibilityIdentifier("link")
                .resolve(ctx)
        }
        defer { host.close() }
        host.open(width: 120, height: 80)
        XCTAssertEqual(qs_is_named_link(host.window, "link", "Help"), 1)
        XCTAssertEqual(qs_mouse_click(host.window, "link"), 1)
        XCTAssertEqual(clicked, [input])
    }
}
