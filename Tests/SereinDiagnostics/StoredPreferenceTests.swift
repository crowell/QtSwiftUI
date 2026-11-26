import Foundation
import SwiftUI
import XCTest

private struct StoredPreference: View {
    @AppStorage("width") private var width = 64
    let read: (Int, Binding<Int>) -> Void
    var body: some View {
        Text("Width \(width)").onChange(of: width, initial: true) { _, latest in read(latest, $width) }
    }
}

final class StoredPreferenceTests: XCTestCase {
    @MainActor func testDefaultStoreBindingAndExternalChange() async throws {
        let suite = "org.qtswiftui.storage." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        var values: [Int] = []
        var binding: Binding<Int>?
        let view = StoredPreference { value, edit in values.append(value); binding = edit }.defaultAppStorage(defaults)
        let window = try await ScreenWindow(view, width: 160, height: 60)
        defer { window.close() }
        try await window.settle()
        XCTAssertEqual(values, [64])
        try XCTUnwrap(binding).wrappedValue = 96
        for _ in 0..<40 where values.last != 96 { try await window.settle() }
        XCTAssertEqual(defaults.integer(forKey: "width"), 96)
        defaults.set(128, forKey: "width")
        for _ in 0..<40 where values.last != 128 { try await window.settle() }
        XCTAssertEqual(values, [64, 96, 128])
    }
}
