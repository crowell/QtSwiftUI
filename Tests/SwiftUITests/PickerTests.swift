import QtBridge
import XCTest
@testable import SwiftUI

final class PickerTests: XCTestCase {
    @MainActor func testPickerInsideCommandMenuChecksAndChangesSelection() async {
        var value = "Blue"
        let host = SwiftUI.Host(title: "Menu") { context in
            WindowGroup { Color.white }
                .commands {
                    CommandMenu("Colors") {
                        Picker("Color", selection: Binding(get: { value }, set: { value = $0 })) {
                            Label("Blue", systemImage: "checkmark").tag("Blue")
                            Text("Red").tag("Red")
                            Text("Green").tag("Green").disabled(true)
                        }
                        .pickerStyle(.inline)
                    }
                }.sceneWindows[0].windowContent(in: context)
        }
        defer { host.close() }
        host.open(width: 260, height: 140)
        _ = qs_click_point(host.window, 16, 10)
        XCTAssertEqual(qs_popup_item_state(host.window, "Blue"), 3)
        XCTAssertEqual(qs_popup_item_state(host.window, "Green"), 0)
        XCTAssertEqual(qs_click_popup_item(host.window, "Red"), 1)
        XCTAssertEqual(value, "Red")
    }

    @MainActor func testMenuSkipsDisabledOptionsAndTracksChangingIDs() async {
        var selection: Int? = 10
        var values = [10, 20, 30]
        let host = SwiftUI.Host(title: "Picker") { context in
            Picker("Quantity", selection: Binding(get: { selection }, set: { selection = $0 })) {
                ForEach(values, id: \.self) { value in
                    Text(verbatim: String(value)).disabled(value == 20)
                }
                Text("None").tag(Int?.none)
            }.pickerStyle(.menu).labelsHidden().resolve(context)
        }
        defer { host.close() }
        host.open(width: 180, height: 80)
        XCTAssertEqual(qs_accessible_value_is(host.window, "Quantity", "10"), 1)
        _ = qs_send_key_sequence(host.window, "Down")
        XCTAssertEqual(selection, 30)
        _ = qs_send_key_sequence(host.window, "Down")
        XCTAssertNil(selection)
        values = [5, 10]
        selection = 5
        host.update()
        qs_flush()
        XCTAssertEqual(qs_accessible_value_is(host.window, "Quantity", "5"), 1)
        _ = qs_send_key_sequence(host.window, "Down")
        XCTAssertEqual(selection, 10)
    }

    @MainActor func testSegmentedAndRadioGroupPropagateMultipleSourceSelection() async {
        struct Source { var value: Binding<String> }
        var first = "Blue", second = "Red"
        var radio = false
        let sources = [Source(value: Binding(get: { first }, set: { first = $0 })),
                       Source(value: Binding(get: { second }, set: { second = $0 }))]
        let host = SwiftUI.Host(title: "Colors") { context in
            let picker = Picker("Colors", sources: sources, selection: \.value) {
                Text("Blue").tag("Blue")
                Text("Red").tag("Red")
            }.labelsHidden()
            if radio { return picker.pickerStyle(.radioGroup).resolve(context) }
            return picker.pickerStyle(.segmented).resolve(context)
        }
        defer { host.close() }
        host.open(width: 180, height: 120)
        for style in [false, true] {
            radio = style
            first = "Blue"
            second = "Red"
            host.update()
            qs_flush()
            XCTAssertEqual(qs_accessible_checked(host.window, "Blue"), 0)
            XCTAssertEqual(qs_accessible_checked(host.window, "Red"), 0)
            XCTAssertEqual(qs_accessible_element(host.window, "Blue", -1, "Toggle"), 1)
            for _ in 0..<12 where second != "Blue" {
                try? await Task.sleep(for: .milliseconds(15))
                qs_flush()
            }
            XCTAssertEqual(first, "Blue")
            XCTAssertEqual(second, "Blue")
            XCTAssertEqual(qs_accessible_checked(host.window, "Blue"), 1)
        }
    }
}
