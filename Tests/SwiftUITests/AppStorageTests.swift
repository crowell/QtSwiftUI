import QtBridge
import XCTest
@testable import SwiftUI

private enum Choice: String { case first, second }
private enum Level: Int { case quiet, normal }
private struct NumberField: View {
    @AppStorage("number") var number = 42
    let changed: (Int, Binding<Int>) -> Void
    var body: some View {
        Text("Number \(number)").onChange(of: number, initial: true) { _, latest in changed(latest, $number) }
    }
}

@MainActor private final class StorageProbe {
    let name = "org.qtswiftui.tests." + UUID().uuidString
    let otherName = "org.qtswiftui.tests." + UUID().uuidString
    var store: UserDefaults { UserDefaults(suiteName: name)! }
    var other: UserDefaults { UserDefaults(suiteName: otherName)! }
    var rootValues: [Int] = []
    var secondValues: [Int] = []
    var nestedValues: [Int] = []
    var binding: Binding<Int>?
}

private struct StoredApp: App {
    let probe = StorageProbe()
    var body: some Scene {
        WindowGroup("Primary") {
            NumberField { value, binding in probe.rootValues.append(value); probe.binding = binding }
            NumberField { value, _ in probe.nestedValues.append(value) }.defaultAppStorage(probe.other)
        }
        .defaultAppStorage(probe.store)
        .defaultLaunchBehavior(.presented)
        Window("Secondary", id: "second") {
            NumberField { value, _ in probe.secondValues.append(value) }
        }
        .defaultLaunchBehavior(.presented)
        .defaultAppStorage(probe.store)
    }
}

final class AppStorageTests: XCTestCase {
    @MainActor func testSceneAndViewStoresExternalUpdatesAndBindings() async throws {
        let app = StoredApp(), probe = app.probe
        defer {
            probe.store.removePersistentDomain(forName: probe.name)
            probe.other.removePersistentDomain(forName: probe.otherName)
        }
        probe.other.set(97, forKey: "number")
        let windows = AppWindows(app)
        defer { windows.finish() }
        XCTAssertEqual(windows.launchWindows()?.count, 2)
        qs_flush()
        XCTAssertEqual(probe.rootValues, [42])
        XCTAssertEqual(probe.secondValues, [42])
        XCTAssertEqual(probe.nestedValues, [97])
        try XCTUnwrap(probe.binding).wrappedValue = 86
        qs_flush()
        XCTAssertEqual(probe.store.integer(forKey: "number"), 86)
        XCTAssertEqual(probe.rootValues.last, 86)
        XCTAssertEqual(probe.secondValues.last, 86)
        let external = probe.store
        external.set(7, forKey: "number")
        for _ in 0..<30 where probe.secondValues.last != 7 {
            try await Task.sleep(for: .milliseconds(25))
            qs_flush()
        }
        XCTAssertEqual(probe.rootValues, [42, 86, 7])
        XCTAssertEqual(probe.secondValues, [42, 86, 7])
        XCTAssertEqual(probe.nestedValues, [97])
    }

    func testSupportedValuesPersistAndNilRemovesKeys() throws {
        let name = "org.qtswiftui.tests." + UUID().uuidString, store = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { store.removePersistentDomain(forName: name) }
        let choice = AppStorage(wrappedValue: Choice.first, "choice", store: store)
        XCTAssertEqual(choice.wrappedValue, .first)
        XCTAssertNil(store.object(forKey: "choice"))
        choice.wrappedValue = .second
        XCTAssertEqual(store.string(forKey: "choice"), "second")
        store.set("unrecognized", forKey: "choice")
        XCTAssertEqual(choice.wrappedValue, .first)
        let level = AppStorage<Level?>("level", store: store)
        level.wrappedValue = .quiet
        XCTAssertEqual(level.wrappedValue, .quiet)
        level.wrappedValue = nil
        XCTAssertNil(store.object(forKey: "level"))
        let number = AppStorage(wrappedValue: 13, "number", store: store)
        store.set("17", forKey: "number")
        XCTAssertEqual(number.wrappedValue, 17)
        let date = Date(timeIntervalSince1970: 12345)
        func verify<T: Equatable>(_ wrapper: AppStorage<T?>, _ value: T) {
            XCTAssertNil(wrapper.wrappedValue)
            wrapper.projectedValue.wrappedValue = value
            XCTAssertEqual(wrapper.wrappedValue, value)
            wrapper.wrappedValue = nil
            XCTAssertNil(wrapper.wrappedValue)
        }
        verify(AppStorage("flag", store: store), true)
        verify(AppStorage("ratio", store: store), 12.5)
        verify(AppStorage("date", store: store), date)
        verify(AppStorage("bytes", store: store), Data([0, 4]))
        verify(AppStorage("title", store: store), "Desktop")
        let url = try XCTUnwrap(URL(string: "https://example.org/p?q=3"))
        let link = AppStorage<URL?>("url", store: store)
        link.wrappedValue = url
        XCTAssertEqual(store.url(forKey: "url"), url)
        verify(AppStorage("local", store: store), URL(fileURLWithPath: "/tmp/report"))
        XCTAssertEqual(AppStorage<URL?>("url", store: UserDefaults(suiteName: name)).wrappedValue, url)
        link.wrappedValue = nil
        XCTAssertNil(store.object(forKey: "url"))
    }
}
