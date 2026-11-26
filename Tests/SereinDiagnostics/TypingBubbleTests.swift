import SwiftUI
import XCTest
@testable import CallDiagnostics

@MainActor @Observable private final class FadingMarker { var shown = false }

final class TypingBubbleTests: XCTestCase {
    @MainActor func testGroupTypingAndPassingTheVisibleAvatarID() async throws {
        let m = ConversationPreviewModel(groupTyping: true)
        let window = try await ScreenWindow(ConversationPreview(model: m), width: 560, height: 502)
        defer { window.close() }
        try await window.settle()
        try window.capture("conversation-typing.png", directoryVariable: "QTSWIFTUI_TYPING_REFERENCE")

        var selected: String?
        let contacts = TimelinePreviewModel.contacts([0, 1, 2, 3])
        let bubble = TypingBubble(conversationType: .group, typingContacts: contacts) { selected = $0 }
        let row = try await ScreenWindow(bubble, width: 320, height: 80)
        defer { row.close() }
        for (x, index) in [(30, 3), (54, 2), (78, 1)] {
            try await row.click(x, 40)
            XCTAssertEqual(selected, contacts[index].id)
        }
    }

    @MainActor func testExplicitOpacityTransitionAppearsAndDisappears() async throws {
        let model = FadingMarker()
        struct Fade: View {
            let model: FadingMarker
            var body: some View {
                ZStack {
                    Color.white
                    if model.shown {
                        Color.black.frame(width: 24, height: 24)
                            .transition(AnyTransition.asymmetric(insertion: .opacity, removal: .opacity))
                            .zIndex(1)
                    }
                }
            }
        }
        let window = try await ScreenWindow(Fade(model: model), width: 48, height: 48, keyboard: true)
        defer { window.close() }
        let before = window.pixel(24, 24) & 255
        XCTAssertGreaterThan(before, 245)
        try await window.settle()
        for shown in [true, false] {
            withAnimation(.linear(duration: 0.3)) { model.shown = shown }
            let deadline = ContinuousClock.now + .seconds(2)
            let target: UInt32 = shown ? 0 : 255
            var intermediate = false
            var result: UInt32 = shown ? 255 : 0
            repeat {
                try await window.settle()
                result = window.pixel(24, 24) & 255
                if result > 4 && result < 251 { intermediate = true }
            } while result != target && ContinuousClock.now < deadline
            XCTAssertEqual(result, target)
            XCTAssertTrue(intermediate, "The transition to shown=\(shown) should pass through an intermediate shade")
        }
    }
}
