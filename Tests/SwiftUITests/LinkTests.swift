import QtBridge
import XCTest
@testable import SwiftUI

final class LinkTests: XCTestCase {
    @MainActor func testAddedAndRemovedLinkTraitsPreserveActivation() async {
        var pressed = 0
        let url = URL(string: "https://example.test")!
        let host = Host(title: "Link roles") { ctx in
            VStack {
                Button("Website") { pressed += 1 }
                    .accessibilityRemoveTraits(.isLink).accessibilityHint("Visit the website")
                    .accessibilityAddTraits(.isLink).accessibilityIdentifier("website")
                Text("Address").accessibilityAddTraits(.isLink).accessibilityIdentifier("address")
                Link("Removed", destination: url)
                    .accessibilityAddTraits(.isLink).accessibilityRemoveTraits(.isLink)
                    .accessibilityIdentifier("removed")
            }.resolve(ctx)
        }
        defer { host.close() }
        host.open(width: 180, height: 100)
        XCTAssertEqual(qs_is_named_link(host.window, "website", "Website"), 1)
        XCTAssertEqual(qs_is_named_link(host.window, "address", "Address"), 1)
        XCTAssertEqual(qs_accessible_element(host.window, "Removed", -1, nil), 1)
        XCTAssertEqual(qs_is_named_link(host.window, "removed", "Removed"), 0)
        XCTAssertEqual(qs_accessible_element(host.window, "Website", -1, "Press"), 1)
        XCTAssertEqual(pressed, 1)
    }

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
