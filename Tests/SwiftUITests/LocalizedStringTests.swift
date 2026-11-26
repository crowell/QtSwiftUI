import CoreFoundation
import Foundation
import SwiftUI
import XCTest

@MainActor final class LocalizedStringTests: XCTestCase {
    func testTranslationTableInterpolationAndVerbatimRendering() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".bundle")
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let info = ["CFBundleIdentifier": "org.qtswiftui.localized-tests", "CFBundleDevelopmentRegion": "en",
                    "CFBundlePackageType": "BNDL"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: directory.appendingPathComponent("Info.plist"))
        for (language, translation) in [("en", "%1$@ found %2$lld"), ("fr", "%2$lld pour %1$@")] {
            let resource = directory.appendingPathComponent(language + ".lproj")
            try FileManager.default.createDirectory(at: resource, withIntermediateDirectories: true)
            try #""%@ has %lld" = "\#(translation)";"#.write(to: resource.appendingPathComponent("Names.strings"),
                                                            atomically: true, encoding: .utf8)
        }
        let bundle = try XCTUnwrap(Bundle(url: directory))
        let name = "Léa", count = 7
        let key: LocalizedStringKey = "\(name) has \(count)"
        let french = Locale(identifier: "fr-FR")
        let english = Locale(identifier: "en-US")
        let text = Text(key, tableName: "Names", bundle: bundle, comment: "Name and count")
        func pixels(_ view: Text, _ locale: Locale) throws -> Data {
            let renderer = ImageRenderer(content: view.environment(\.locale, locale)
                .foregroundStyle(.black).frame(width: 240, height: 42).background(Color.white))
            let image = try XCTUnwrap(renderer.cgImage)
            let data = try XCTUnwrap(image.dataProvider?.data)
            return Data(bytes: CFDataGetBytePtr(data), count: CFDataGetLength(data))
        }

        XCTAssertEqual(try pixels(text, french), try pixels(Text(verbatim: "7 pour Léa"), french))
        XCTAssertEqual(try pixels(text, english), try pixels(Text(verbatim: "Léa found 7"), english))
        XCTAssertNotEqual(try pixels(text, english), try pixels(text, french))
        let progress = 2.5
        XCTAssertEqual(try pixels(Text("Progress \(progress, specifier: "%.1f")%"), english),
                       try pixels(Text(verbatim: "Progress 2.5%"), english))
        XCTAssertEqual(try pixels(Text("Total \(count, format: .number)"), french),
                       try pixels(Text(verbatim: "Total 7"), french))
        XCTAssertEqual(key, key)
        XCTAssertNotEqual(key, "\(name) has \(count)")
        let formatted: LocalizedStringKey = "Total \(count, format: .number)"
        XCTAssertEqual(formatted, "Total \(count, format: .number)")
        XCTAssertNotEqual(key, "\(name) has \(count + 1)")
    }
}
