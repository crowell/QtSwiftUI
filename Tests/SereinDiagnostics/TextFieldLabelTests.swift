import SwiftUI
import XCTest
#if os(Linux)
@testable import SwiftUI
import QtBridge
#else
import AppKit
#endif

private struct CaptionLabel: View {
    @Environment(\.locale) var locale
    var body: some View { Text(verbatim: locale.identifier) }
}

private struct ForwardingFieldStyle: TextFieldStyle {
    func _body(configuration: TextField<_Label>) -> some View { configuration.textFieldStyle(.plain) }
}

@MainActor private final class FieldLabelModel {
    var text = ""
    var selection: TextSelection?
}

final class TextFieldLabelTests: XCTestCase {
    @MainActor private func width(of view: some View) async throws -> CGFloat {
        var result: CGFloat?
        let screen = try await ScreenWindow(view.textFieldStyle(ForwardingFieldStyle()).fixedSize()
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { result = $0 }, width: 240, height: 80)
        defer { screen.close() }
        try await screen.settle()
        return try XCTUnwrap(result)
    }

    @MainActor func testPromptUsesFirstDrawnTextAndExplicitPromptTakesPrecedence() async throws {
        let text = Binding<String>.constant("")
        let name = try await width(of: TextField("Account", text: text))
        let empty = try await width(of: TextField("", text: text))
        let localeID = "fr_FR"
        let language = try await width(of: TextField(localeID, text: text))
        let label = try await width(of: TextField(text: text) { Label("Account", systemImage: "star") })
        let siblings = try await width(of: TextField(text: text, axis: .vertical) {
            HStack { Image(systemName: "star"); Text("Account"); Text("Second text should be ignored") }
        })
        let background = try await width(of: TextField(text: text) { Text("Front").background(Text("Account")) })
        let noText = try await width(of: TextField(text: text) { Image(systemName: "star").accessibilityLabel("Favorite") })
        let emptyFirst = try await width(of: TextField(text: text) { Text(""); Text("Account") })
        let nested = try await width(of: TextField(text: text) { CaptionLabel().environment(\.locale, Locale(identifier: localeID)) })
        let explicit = try await width(of: TextField(text: text, prompt: Text("Account")) { Text("Different") })
        for measured in [label, siblings, background, explicit] { XCTAssertEqual(measured, name, accuracy: 0.5) }
        XCTAssertEqual(nested, language, accuracy: 0.5)
        XCTAssertEqual(emptyFirst, empty)
        XCTAssertEqual(noText, empty)
    }

    @MainActor func testPlaceholderFontAffectsOnlyAnEmptyField() async throws {
        let title = "Caption"
        let normal = try await width(of: TextField(title, text: .constant("")))
        let large = try await width(of: TextField(text: .constant("")) { Text(title).font(.system(size: 36)) })
        let typed = try await width(of: TextField(text: .constant(title)) { Text(title).font(.system(size: 36)) })
        XCTAssertGreaterThan(large, normal * 1.5)
        XCTAssertEqual(typed, normal, accuracy: 0.5)
    }

    @MainActor func testSecureLabelPromptsAndSelectionBinding() async throws {
        let model = FieldLabelModel()
        let text = Binding(get: { model.text }, set: { model.text = $0 })
        let selection = Binding(get: { model.selection }, set: { model.selection = $0 })
        let screen = try await ScreenWindow(VStack {
            SecureField(text: text, prompt: Text("Secret")) { Text("Password") }
            TextField(text: text, selection: selection, axis: .horizontal) { Text("Draft") }
        }.textFieldStyle(.plain), width: 180, height: 80, keyboard: true)
        defer { screen.close() }
        #if os(Linux)
        XCTAssertEqual(qs_accessible_element(screen.host.window, "Password", 0, nil), 1)
        XCTAssertEqual(qs_accessible_element(screen.host.window, "Draft", 0, nil), 1)
        #else
        func secureField(in parent: NSView) -> NSSecureTextField? {
            if let field = parent as? NSSecureTextField { return field }
            return parent.subviews.compactMap { secureField(in: $0) }.first
        }
        XCTAssertEqual(secureField(in: screen.hosting)?.placeholderString, "Secret")
        #endif
        try await screen.click(50, 51)
        try await screen.type("Draft")
        XCTAssertEqual(model.text, "Draft")
        guard let value = model.selection, case .selection(let range) = value.indices else { return XCTFail("Missing insertion point") }
        XCTAssertEqual(range, model.text.endIndex..<model.text.endIndex)
    }

    @MainActor func testBorderedAndSquareFieldCorners() async throws {
        func corners(_ style: some TextFieldStyle) async throws -> [UInt32] {
            let screen = try await ScreenWindow(TextField("Caption", text: .constant("")).textFieldStyle(style)
                .frame(width: 120).background(Color.orange), width: 140, height: 60)
            defer { screen.close() }
            var pixels: [UInt32] = []
            for y in 13..<27 { for x in 10..<17 { pixels.append(screen.pixel(x, y)) } }
            return pixels
        }
        let square = try await corners(.squareBorder)
        let bordered = try await corners(.bordered)
        let rounded = try await corners(.roundedBorder)
        XCTAssertEqual(bordered, rounded)
        let automatic = try await corners(.automatic)
        let plain = try await corners(.plain)
        XCTAssertEqual(square, automatic)
        XCTAssertNotEqual(square, plain)
    }
}
