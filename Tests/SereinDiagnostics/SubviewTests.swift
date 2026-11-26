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
    @MainActor func testExplicitAndForEachTagsPreserveOptionalTypes() async throws {
        var tags: [ContainerValues] = []
        let rows = Group {
            Text("Plain")
            Text("Seven").tag(7)
            Text("Eight").tag(8, includeOptional: false)
            Text("None").tag(Int?.none)
            ForEach([3, 5], id: \.self) { id in Text(String(id)) }
        }
        let view = Group(subviews: rows) { children in
            let _ = { tags = children.map(\.containerValues) }()
            Color.white.frame(width: 5, height: 5)
        }
        _ = try XCTUnwrap(ImageRenderer(content: view).cgImage)
        XCTAssertEqual(tags.count, 6)
        guard tags.count == 6 else { return }
        XCTAssertFalse(tags[0].hasTag(Int?.none))
        XCTAssertTrue(tags[1].hasTag(7))
        XCTAssertTrue(tags[1].hasTag(Optional(7)))
        XCTAssertTrue(tags[2].hasTag(8))
        XCTAssertFalse(tags[2].hasTag(Optional(8)))
        XCTAssertTrue(tags[3].hasTag(Int?.none))
        XCTAssertEqual(tags[4].tag(for: Int.self), 3)
        XCTAssertEqual(tags[5].tag(for: Int.self), 5)
    }

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
