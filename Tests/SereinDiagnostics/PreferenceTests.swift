import XCTest
#if os(Linux)
import QtBridge
@testable import SwiftUI
#else
import AppKit
import SwiftUI
#endif

private enum Words: PreferenceKey {
    static let defaultValue = ""
    static func reduce(value: inout String, nextValue: () -> String) { value += "|" + nextValue() }
}

@MainActor private struct PreferenceProbe: View {
    let active: Bool
    let record: (String) -> Void
    var body: some View {
        VStack {
            if active {
                GeometryReader { _ in Color.clear.preference(key: Words.self, value: "geometry") }
                VStack {
                    Text("inner").preference(key: Words.self, value: "inner")
                }.preference(key: Words.self, value: "outer")
                EmptyView().preference(key: Words.self, value: "empty")
                Color.clear.transformPreference(Words.self) { $0 += "transform" }
            }
        }.onPreferenceChange(Words.self, perform: record)
    }
}

final class PreferenceTests: XCTestCase {
    @MainActor func testOrderOverrideRemovalAndUnchangedDelivery() async {
        var values: [String] = []
        func probe(_ enabled: Bool) -> PreferenceProbe { PreferenceProbe(active: enabled) { values.append($0) } }
        #if os(Linux)
        var active = false
        let host = Host(title: "Preferences") { probe(active).resolve($0) }
        host.open(width: 120, height: 80)
        defer { host.close() }
        func set(_ enabled: Bool) {
            active = enabled
            host.update()
            qs_flush()
        }
        #else
        _ = NSApplication.shared
        let host = NSHostingView(rootView: probe(false))
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 120, height: 80),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        defer { withExtendedLifetime(window) {} }
        func set(_ enabled: Bool) {
            host.rootView = probe(enabled)
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.04))
        }
        #endif
        set(false)
        XCTAssertEqual(values, [""])
        set(true)
        set(true)
        set(false)
        XCTAssertEqual(values, ["", "geometry|outer|transform", ""])
    }
}
