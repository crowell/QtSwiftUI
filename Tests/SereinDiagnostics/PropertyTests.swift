import XCTest
#if os(Linux)
import QtBridge
@testable import SwiftUI
#else
import SwiftUI
#endif

private struct Counter: DynamicProperty {
    @State var count = 3
    private(set) var doubled = -1
    mutating func update() { doubled = count * 2 }
}

private struct Fields: DynamicProperty {
    var counter = Counter()
}

@MainActor private final class Capture { var value: Int? }

private struct CounterView: View {
    var fields = Fields()
    let capture: Capture
    var body: some View {
        let _ = capture.value = fields.counter.doubled
        VStack {
            Text("\(fields.counter.doubled)").accessibilityIdentifier("count")
            Button("Increment") { fields.counter.count += 1 }.accessibilityIdentifier("increment")
        }
    }
}

final class PropertyTests: XCTestCase {
    @MainActor func testNestedUpdatesBeforeBody() async throws {
        let capture = Capture()
        #if os(Linux)
        let host = Host(title: "Property updates") { CounterView(capture: capture).resolve($0) }
        defer { host.close() }
        host.open(width: 160, height: 90)
        XCTAssertEqual(capture.value, 6)
        XCTAssertEqual(qs_click(host.window, "increment"), 1)
        XCTAssertEqual(qs_read_text(host.window, "count", "8"), 1)
        XCTAssertEqual(capture.value, 8)
        #else
        let renderer = ImageRenderer(content: CounterView(capture: capture))
        XCTAssertNotNil(renderer.cgImage)
        XCTAssertEqual(capture.value, 6)
        #endif
    }
}
