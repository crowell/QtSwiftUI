import XCTest
import SwiftUI
#if !os(Linux)
import AppKit
#endif

private struct BoxedField: TextFieldStyle {
    func _body(configuration: TextField<_Label>) -> some View {
        configuration.textFieldStyle(.plain).padding(4).background(Color.white)
    }
}

final class ControlStyleTests: XCTestCase {
    @MainActor func testBusyIndicatorFootprints() async throws {
        var frames: [ControlSize: CGSize] = [:]
        let view = HStack {
            ForEach(ControlSize.allCases, id: \.self) { control in
                ProgressView().controlSize(control)
                    .onGeometryChange(for: CGSize.self) { $0.size } action: { frames[control] = $0 }
            }
        }
        let window = try await ScreenWindow(view, width: 200, height: 44)
        defer { window.close() }
        let diameters: [CGFloat] = [10, 16, 32, 32, 32]
        for (control, diameter) in zip(ControlSize.allCases, diameters) {
            XCTAssertEqual(frames[control], CGSize(width: diameter, height: diameter))
        }
        XCTAssertLessThan(ControlSize.mini, .extraLarge)
    }

    @MainActor func testStandardControlsRespondToSize() async throws {
        var sizes: [ControlSize: CGSize] = [:]
        let view = HStack {
            ForEach([ControlSize.mini, .regular, .extraLarge], id: \.self) { control in
                Toggle("Missed", isOn: .constant(false)).fixedSize().controlSize(control)
                    .onGeometryChange(for: CGSize.self) { $0.size } action: { sizes[control] = $0 }
            }
        }
        let window = try await ScreenWindow(view, width: 360, height: 60)
        defer { window.close() }
        let mini = try XCTUnwrap(sizes[.mini]), regular = try XCTUnwrap(sizes[.regular]), large = try XCTUnwrap(sizes[.extraLarge])
        XCTAssertLessThan(mini.height, regular.height)
        XCTAssertLessThanOrEqual(regular.height, large.height)
    }

    @MainActor func testCustomFieldStyleRetainsTextBinding() async throws {
        var value = ""
        let view = TextField("Find", text: Binding { value } set: { value = $0 }).textFieldStyle(BoxedField())
        let window = try await ScreenWindow(view, width: 150, height: 40)
        defer { window.close() }
        try await window.click(40, 19)
        try await window.type("Alice")
        XCTAssertEqual(value, "Alice")
    }

    @MainActor func testBlurSoftensAHighContrastEdge() async throws {
        let view = Color.white.overlay { Color.black.frame(width: 30, height: 30) }
            .frame(width: 80, height: 60).blur(radius: 4)
        #if os(Linux)
        let window = try await ScreenWindow(view, width: 80, height: 60)
        defer { window.close() }
        func shade(_ x: Int) -> UInt32 { window.pixel(x, 30) & 255 }
        #else
        let image = try XCTUnwrap(ImageRenderer(content: view).cgImage)
        let bitmap = NSBitmapImageRep(cgImage: image)
        func shade(_ x: Int) -> UInt32 {
            UInt32(((bitmap.colorAt(x: x, y: 30)?.usingColorSpace(.sRGB)?.blueComponent ?? 0) * 255).rounded())
        }
        #endif
        XCTAssertLessThan(shade(40), 5)
        XCTAssertLessThan(shade(27), shade(24))
        XCTAssertLessThan(shade(24), 235)
        XCTAssertGreaterThan(shade(10), 250)
    }
}
