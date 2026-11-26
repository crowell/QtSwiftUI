import XCTest
import QtBridge
@testable import SwiftUI

private struct Counter: View {
    @State var count = 0
    let name: String
    var body: some View {
        HStack {
            Text("\(name): \(count)").accessibilityIdentifier("text-" + name)
            Button("Add") { count += 1 }.accessibilityIdentifier("add-" + name)
        }
    }
}
private struct Fixture: View {
    @State var names = ["A", "B"]
    @State var text = ""
    @State var visible = true
    var body: some View {
        VStack {
            TextField("Draft", text: $text).accessibilityIdentifier("edit")
            Text(text).accessibilityIdentifier("echo")
            Toggle("Rows", isOn: $visible).accessibilityIdentifier("toggle")
            if visible {
                ForEach(names, id: \.self) { Counter(name: $0) }
            }
            Button("Reverse") { names.reverse() }.accessibilityIdentifier("reverse")
        }
    }
}
final class RuntimeTests: XCTestCase {
    func testQtEventsBindingsAndKeyedState() async {
        await MainActor.run {
            let host = Host(title: "Test") { Fixture().resolve($0) }
            defer { host.close() }
            host.open(width: 400, height: 300)
            XCTAssertEqual(qs_click(host.window, "add-A"), 1)
            XCTAssertEqual(qs_click(host.window, "reverse"), 1)
            XCTAssertEqual(qs_read_text(host.window, "text-A", "A: 1"), 1)
            XCTAssertEqual(qs_read_text(host.window, "text-B", "B: 0"), 1)
            XCTAssertEqual(qs_enter(host.window, "edit", "Linux & Qt"), 1)
            XCTAssertEqual(qs_read_text(host.window, "echo", "Linux & Qt"), 1)
            XCTAssertEqual(qs_click(host.window, "toggle"), 1)
            XCTAssertEqual(qs_click(host.window, "add-A"), 0)
            XCTAssertEqual(qs_click(host.window, "toggle"), 1)
            XCTAssertEqual(qs_read_text(host.window, "text-A", "A: 0"), 1)
        }
    }
}
