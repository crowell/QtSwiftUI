import Foundation
import SwiftUI
import UniformTypeIdentifiers
import XCTest

private func pasteControl(disabled: Bool) -> some View {
    PasteButton(supportedContentTypes: disabled ? [] : [.plainText]) { _ in }
}

final class PasteButtonLayoutTests: XCTestCase {
    @MainActor func testProviderButtonHasAnIntrinsicDesktopControlSize() async {
        let renderer = ImageRenderer(content: pasteControl(disabled: true))
        let image = renderer.cgImage
        XCTAssertGreaterThan(image?.width ?? 0, 20)
        XCTAssertGreaterThan(image?.height ?? 0, 12)
    }
}
