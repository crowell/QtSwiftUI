import SwiftUI
import XCTest
#if os(Linux)
import QtBridge
@testable import SwiftUI
#else
import AppKit
#endif

private extension ContainerValues {
    @Entry var fixtureWidth = 0
}
private extension EnvironmentValues {
    @Entry var fixtureDark = false
}

private struct Row: View {
    @Environment(\.fixtureDark) var dark
    let width: Int
    var body: some View {
        (dark ? Color.black : Color.white).frame(width: 10, height: 10)
            .containerValue(\.fixtureWidth, width).padding(0)
    }
}

final class SubviewTests: XCTestCase {
    @MainActor func testCollectionMetadataSlicesAndOriginalEnvironment() async throws {
        var values: [Int] = []
        var ids: [Subview.ID] = []
        let rows = Group {
            EmptyView()
            Row(width: 7)
            ForEach([3, 5], id: \.self) { Row(width: $0) }
            VStack { Row(width: 9) }
        }.environment(\.fixtureDark, true)
        let view = Group(subviews: rows) { children in
            let _ = { values = children.map(\.containerValues.fixtureWidth); ids = children.map(\.id) }()
            HStack(spacing: 0) { children[1..<3] }
                .environment(\.fixtureDark, false)
        }.frame(width: 20, height: 10).background(Color.white)
        #if os(Linux)
        let host = Host(title: "Subviews") { view.resolve($0) }
        host.open(width: 20, height: 10)
        defer { host.close() }
        func black(_ x: Int) -> Bool { qs_pixel(host.window, Int32(x), 5) & 255 < 64 }
        #else
        let image = NSBitmapImageRep(cgImage: try XCTUnwrap(ImageRenderer(content: view).cgImage))
        func black(_ x: Int) -> Bool { image.colorAt(x: x, y: 5)!.redComponent < 0.25 }
        #endif
        XCTAssertEqual(values, [7, 3, 5, 0])
        XCTAssertEqual(Set(ids).count, 4)
        XCTAssertTrue(black(5))
        XCTAssertTrue(black(15))
    }
}
