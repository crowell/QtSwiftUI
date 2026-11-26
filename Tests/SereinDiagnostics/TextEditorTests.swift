import XCTest
import SwiftUI
#if os(Linux)
@testable import SwiftUI
import QtBridge
#else
import AppKit
#endif

@Observable private final class EditorModel {
    var text = ""
    var focused = false
    var submits = 0
}

private struct Notes: View {
    @Bindable var model: EditorModel
    @FocusState private var focused: Bool
    var body: some View {
        TextEditor(text: $model.text)
            .scrollContentBackground(.hidden)
            .focused($focused)
            .onChange(of: focused) { _, value in model.focused = value }
            .onSubmit { model.submits += 1 }
            .frame(width: 160, height: 80)
            .background(Color.green)
    }
}

private struct EditorSizing: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let child = subviews[0]
        XCTAssertEqual(child.sizeThatFits(.unspecified), CGSize(width: 0, height: 36))
        XCTAssertEqual(child.sizeThatFits(.init(width: 7, height: nil)), CGSize(width: 7, height: 36))
        XCTAssertEqual(child.sizeThatFits(.zero), .zero)
        XCTAssertEqual(child.sizeThatFits(.init(width: nil, height: 10)), CGSize(width: 0, height: 10))
        XCTAssertEqual(child.sizeThatFits(.infinity), CGSize(width: CGFloat.infinity, height: CGFloat.infinity))
        return CGSize(width: 100, height: 60)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews[0].place(at: bounds.origin, proposal: ProposedViewSize(bounds.size))
    }
}

final class TextEditorTests: XCTestCase {
    @MainActor func testIntrinsicSizeCountsHardLineBreaks() async throws {
        let view = EditorSizing { TextEditor(text: .constant("A long unbroken line\nTwo\n")) }
        #if os(Linux)
        let host = Host(title: "Editor sizing") { view.resolve($0) }
        defer { host.close() }
        host.open(width: 100, height: 60)
        #else
        XCTAssertEqual(NSHostingView(rootView: view).fittingSize, CGSize(width: 100, height: 60))
        #endif
    }

    @MainActor func testMultilineUnicodeBindingAndReturn() async throws {
        let model = EditorModel()
        let view = Notes(model: model)
        #if os(Linux)
        let host = Host(title: "Notes") { view.resolve($0) }
        defer { host.close() }
        host.open(width: 160, height: 80)
        XCTAssertEqual(qs_pixel(host.window, 145, 70), Color.green.argb(.light))
        XCTAssertEqual(qs_click_point(host.window, 10, 8), 1)
        func type(_ string: String) { XCTAssertEqual(string.withCString { qs_commit_text(host.window, $0, string.utf8.count) }, 1) }
        func newline() { XCTAssertEqual(qs_send_key_sequence(host.window, "Return"), 1) }
        #else
        let hosting = NSHostingView(rootView: view)
        let window = NSWindow(contentRect: CGRect(x: 0, y: 0, width: 160, height: 80), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = hosting
        window.orderFrontRegardless()
        defer { window.close() }
        hosting.layoutSubtreeIfNeeded()
        func find(_ view: NSView) -> NSTextView? {
            if let editor = view as? NSTextView { return editor }
            return view.subviews.lazy.compactMap(find).first
        }
        let editor = try XCTUnwrap(find(hosting))
        XCTAssertTrue(window.makeFirstResponder(editor))
        func type(_ string: String) { editor.insertText(string, replacementRange: editor.selectedRange()) }
        func newline() { editor.insertNewline(nil) }
        #endif
        let first = "Audio\u{a0}delay 🎧"
        type(first)
        newline()
        type("Second line")
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertTrue(model.focused)
        XCTAssertEqual(model.text, first + "\nSecond line")
        XCTAssertEqual(model.submits, 0)
        model.text = "Reset"
        try await Task.sleep(for: .milliseconds(50))
        #if os(Linux)
        qs_flush()
        _ = qs_send_key_sequence(host.window, "Ctrl+End")
        #else
        editor.setSelectedRange(NSRange(location: editor.string.utf16.count, length: 0))
        #endif
        type(" ✓")
        try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(model.text, "Reset ✓")
    }
}
