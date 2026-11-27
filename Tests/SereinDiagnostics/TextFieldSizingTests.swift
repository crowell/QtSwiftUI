import SwiftUI
import XCTest
@testable import CallDiagnostics

private struct MeasureField: Layout {
    let proposal: ProposedViewSize
    let measured: (CGSize) -> Void

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let field = subviews.first else { return .zero }
        let size = field.sizeThatFits(self.proposal)
        measured(size)
        return size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, proposal: self.proposal)
    }
}

private struct LiveCaption: View {
    @State var text = ""
    @FocusState var focused: Bool

    var body: some View {
        ZStack {
            Color.white
            TextField("", text: $text, axis: .vertical)
                .textFieldStyle(.plain).font(.system(size: 27))
                .foregroundStyle(Color.black).multilineTextAlignment(.center)
                .fixedSize().frame(minWidth: 20)
                .overlay(Rectangle().stroke(Color.gray, lineWidth: 1))
                .rotationEffect(.zero)
                .focused($focused).onAppear { focused = true }
        }
    }
}

final class TextFieldSizingTests: XCTestCase {
    @MainActor private func measure<Field: View>(
        _ proposal: ProposedViewSize = .unspecified, @ViewBuilder _ field: () -> Field
    ) async throws -> CGSize {
        var measured: CGSize?
        let reader = MeasureField(proposal: proposal) { measured = $0 }
        let screen = try await ScreenWindow(reader { field().font(.system(size: 27)).textFieldStyle(.plain) },
                                            width: 280, height: 130)
        defer { screen.close() }
        return try XCTUnwrap(measured)
    }

    @MainActor func testIdealWidthUsesVisibleTextAndKeepsSecureValuesPrivate() async throws {
        for axis in [Axis.horizontal, .vertical] {
            let empty = try await measure { TextField("", text: .constant(""), axis: axis) }
            let prompt = try await measure { TextField("Name", text: .constant(""), prompt: Text("Waterfall!"), axis: axis) }
            let value = try await measure { TextField("Caption", text: .constant("Waterfall!"), axis: axis) }
            let short = try await measure { TextField("Long placeholder", text: .constant("I"), axis: axis) }
            XCTAssertEqual(empty.width, 4, accuracy: 0.5)
            XCTAssertEqual(value, prompt)
            XCTAssertGreaterThan(short.width, empty.width)
            XCTAssertGreaterThan(prompt.width, short.width + 60)
            XCTAssertEqual(empty.height, value.height)
        }
        for password in ["", "Waterfall!", "Two\nlines"] {
            let ideal = try await measure { SecureField("Hint", text: .constant(password)) }
            let finite = try await measure(.init(width: 90, height: 5)) { SecureField("Hint", text: .constant(password)) }
            XCTAssertEqual(ideal.width, 0)
            XCTAssertEqual(finite.width, 90)
            XCTAssertEqual(finite.height, ideal.height)
        }
    }

    @MainActor func testSereinCaptionUsingItsBundledFont() async throws {
        AxoFonts.register()
        let caption = try await measure {
            TextField("", text: .constant("Waterfall"), axis: .vertical)
                .font(.custom("Inter-SemiBold", fixedSize: 49))
        }
        // The macOS 27.2 field measures 218.27 by 59 points for this face.
        XCTAssertEqual(caption.width, 218.27, accuracy: 0.5)
        XCTAssertEqual(caption.height, 59, accuracy: 1)
    }

    @MainActor func testFixedSizeFieldPaintsTypedText() async throws {
        let screen = try await ScreenWindow(LiveCaption(), width: 240, height: 90, keyboard: true)
        defer { screen.close() }
        try await screen.settle()
        try await screen.type("Waterfall")
        // Sample the interior to exclude the insertion point and the resizing border.
        var ink = 0
        for y in stride(from: 38, to: 53, by: 2) {
            for x in stride(from: 82, to: 158, by: 2) {
                if screen.pixel(x, y) & 255 < 125 { ink += 1 }
            }
        }
        XCTAssertGreaterThan(ink, 25)
    }

    @MainActor func testVerticalFieldWrapsClampsAndReservesLines() async throws {
        let one = try await measure { TextField("", text: .constant("A"), axis: .vertical) }
        let limited = try await measure { TextField("", text: .constant("A\nA\nA much longer line"), axis: .vertical).lineLimit(2) }
        XCTAssertEqual(limited.width, one.width, accuracy: 0.5)
        XCTAssertEqual(limited.height, one.height * 2, accuracy: 1)
        let narrow = try await measure(.init(width: 80, height: nil)) {
            TextField("", text: .constant("Waterfall Waterfall Waterfall"), axis: .vertical)
        }
        XCTAssertEqual(narrow.width, 80)
        XCTAssertGreaterThan(narrow.height, 2 * one.height)
        let tiny = ProposedViewSize(width: 80, height: 5)
        let clamped = try await measure(tiny) { TextField("", text: .constant("A"), axis: .vertical).lineLimit(2) }
        let reserved = try await measure(tiny) { TextField("", text: .constant("A"), axis: .vertical).lineLimit(2...3) }
        let horizontal = try await measure(tiny) { TextField("", text: .constant("A\nB")) }
        XCTAssertEqual(clamped.height, 5)
        XCTAssertEqual(reserved.height, 2 * one.height, accuracy: 1)
        XCTAssertEqual(horizontal.height, one.height, accuracy: 1)
    }
}
