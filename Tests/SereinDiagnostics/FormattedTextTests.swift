import CoreFoundation
import Foundation
import SwiftUI
import XCTest

private struct MarkedFormat: FormatStyle {
    var language = "initial"
    func locale(_ value: Locale) -> Self { Self(language: value.identifier) }
    func format(_ input: Int) -> AttributedString {
        var marked = AttributedString("\(input)")
        marked.foregroundColor = .red
        marked.backgroundColor = .yellow
        marked.font = .system(size: 20, weight: .bold)
        return AttributedString(language + " ") + marked
    }
}

private final class NoRepresentation: Formatter {
    override func string(for obj: Any?) -> String? { nil }
}

final class FormattedTextTests: XCTestCase {
    private let french = Locale(identifier: "fr_FR")
    private let zone = TimeZone(secondsFromGMT: -6 * 3600)!
    private let calendar = Calendar(identifier: .buddhist)

    @MainActor private func pixels(_ view: some View) throws -> Data {
        let renderer = ImageRenderer(content: view.font(.system(size: 18))
            .environment(\.locale, french).environment(\.timeZone, zone).environment(\.calendar, calendar)
            .frame(width: 330, height: 42).background(Color.white))
        let data = try XCTUnwrap(renderer.cgImage?.dataProvider?.data)
        return Data(bytes: CFDataGetBytePtr(data), count: CFDataGetLength(data))
    }

    @MainActor func testNumberAndDateFollowTheViewsEnvironment() async throws {
        let number = IntegerFormatStyle<Int>.number.locale(Locale(identifier: "en_US"))
        let numberText = Text(verbatim: number.locale(french).format(12345))
        XCTAssertEqual(try pixels(Text(12345, format: number)), try pixels(numberText))

        let date = Date(timeIntervalSince1970: 0)
        let style = Date.FormatStyle(date: .numeric, time: .shortened, locale: Locale(identifier: "en_US"),
                                     calendar: Calendar(identifier: .gregorian), timeZone: TimeZone(secondsFromGMT: 0)!)
        var localized = style.locale(french)
        localized.calendar = calendar
        localized.timeZone = zone
        XCTAssertEqual(try pixels(Text(date, format: style)), try pixels(Text(verbatim: localized.format(date))))
        // Apple's attributed date format keeps the style's calendar and zone.
        XCTAssertEqual(try pixels(Text(date, format: style.attributed)),
                       try pixels(Text(style.attributed.locale(french).format(date))))
    }

    @MainActor func testReferenceAndObjectFormattersUseTheEnvironmentAndHandleMissingOutput() async throws {
        let date = Date(timeIntervalSince1970: 0)
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US")
        df.dateFormat = "yyyy/MM/dd HH:mm"
        XCTAssertEqual(try pixels(Text(date, formatter: df)), try pixels(Text(verbatim: "2512/12/31 18:00")))
        XCTAssertEqual(df.calendar.identifier, calendar.identifier)
        XCTAssertEqual(df.timeZone.secondsFromGMT(for: date), zone.secondsFromGMT(for: date))
        let nf = NumberFormatter()
        nf.locale = Locale(identifier: "en_US")
        nf.numberStyle = .decimal
        let value = NSNumber(value: 12345)
        XCTAssertEqual(try pixels(Text(value, formatter: nf)), try pixels(Text(12345, format: .number)))
        XCTAssertEqual(nf.locale.identifier, french.identifier)
        XCTAssertEqual(try pixels(Text("At \(date, formatter: df)")), try pixels(Text(verbatim: "At 2512/12/31 18:00")))
        XCTAssertEqual(try pixels(Text("Empty [\(date, formatter: NoRepresentation())]")), try pixels(Text(verbatim: "Empty []")))
    }

    @MainActor func testAttributedOutputRetainsRunsInTextAndInterpolation() async throws {
        let style = MarkedFormat()
        let formatted = style.locale(french).format(27)
        let output = try pixels(Text(27, format: style))
        XCTAssertEqual(output, try pixels(Text(formatted)))
        XCTAssertNotEqual(output, try pixels(Text(verbatim: String(formatted.characters))))
        let expected = AttributedString("Room: ") + formatted + AttributedString("!")
        XCTAssertEqual(try pixels(Text("Room: \(27, format: style)!")), try pixels(Text(expected)))
        XCTAssertEqual(try pixels(Text("Room: \(formatted)!")), try pixels(Text(expected)))
        let lastRun = try XCTUnwrap(formatted.runs.last)
        let substring = formatted[lastRun.range]
        XCTAssertEqual(try pixels(Text("Room \(substring)")), try pixels(Text(AttributedString("Room ") + AttributedString(substring))))
    }

    @MainActor func testFormattedTextInCanvasUsesTheGraphicsEnvironment() async throws {
        let style = MarkedFormat()
        func canvas(_ text: Text) -> some View {
            Canvas { context, size in
                context.draw(text, at: CGPoint(x: size.width / 2, y: size.height / 2))
            }
        }
        let expected = style.locale(french).format(27)
        XCTAssertEqual(try pixels(canvas(Text(27, format: style))), try pixels(canvas(Text(expected))))
        XCTAssertNotEqual(try pixels(canvas(Text(27, format: style))), try pixels(canvas(Text(verbatim: "initial 27"))))
    }
}
