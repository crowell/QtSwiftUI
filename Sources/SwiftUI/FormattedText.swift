import Foundation

#if os(Linux)
// Corelibs provides Date's NSDate bridge. Darwin also exposes this public conformance.
extension Date: @retroactive ReferenceConvertible {
    public typealias ReferenceType = NSDate
}
#endif

enum TextContent {
    case plain(String)
    case attributed(AttributedString)

    var string: String {
        switch self {
        case .plain(let value): value
        case .attributed(let value): String(value.characters)
        }
    }

    var attributed: AttributedString? {
        if case .attributed(let value) = self { return value }
        return nil
    }

    var attributedString: AttributedString {
        switch self {
        case .plain(let value): AttributedString(value)
        case .attributed(let value): value
        }
    }

    mutating func append(_ other: Self) {
        switch (self, other) {
        case (.plain(var result), .plain(let suffix)):
            result += suffix
            self = .plain(result)
        default:
            self = .attributed(attributedString + other.attributedString)
        }
    }
}

enum TextSource {
    case plain(String)
    case attributed(AttributedString)
    case localized(LocalizedStringKey, String?, Bundle?)
    case formatted(attributed: Bool, (EnvironmentValues) -> TextContent)

    var usesAttributedText: Bool {
        switch self {
        case .plain: false
        case .attributed: true
        case .localized(let key, _, _): key.usesAttributedText
        case .formatted(let attributed, _): attributed
        }
    }

    static func formatted(_ subject: Any, using formatter: Formatter) -> Self {
        .formatted(attributed: false) { environment in
            // SwiftUI updates the supplied Foundation formatter when it resolves the text.
            if let date = formatter as? DateFormatter {
                date.locale = environment.locale
                date.calendar = environment.calendar
                date.timeZone = environment.timeZone
            } else if let number = formatter as? NumberFormatter {
                number.locale = environment.locale
            }
            return .plain(formatter.string(for: subject) ?? "")
        }
    }

    func resolve(in environment: EnvironmentValues) -> TextContent {
        switch self {
        case .plain(let value): .plain(value)
        case .attributed(let value): .attributed(value)
        case .localized(let key, let table, let bundle): key.resolve(in: environment, table: table, bundle: bundle)
        case .formatted(_, let format): format(environment)
        }
    }
}

extension Text {
    public init<Subject>(_ subject: Subject, formatter: Formatter) where Subject: ReferenceConvertible {
        self.init(source: .formatted(subject, using: formatter))
    }

    public init<Subject>(_ subject: Subject, formatter: Formatter) where Subject: NSObject {
        self.init(source: .formatted(subject, using: formatter))
    }

    public init<F>(_ input: F.FormatInput, format: F)
    where F: FormatStyle, F.FormatInput: Equatable, F.FormatOutput == String {
        self.init(source: .formatted(attributed: false) { environment in
            .plain(environment.format(input, with: format))
        })
    }

    public init<F>(_ input: F.FormatInput, format: F)
    where F: FormatStyle, F.FormatInput: Equatable, F.FormatOutput == AttributedString {
        self.init(source: .formatted(attributed: true) { environment in
            .attributed(format.locale(environment.locale).format(input))
        })
    }
}

extension EnvironmentValues {
    func format<F: FormatStyle>(_ input: F.FormatInput, with style: F) -> String where F.FormatOutput == String {
        if var dateStyle = style as? Date.FormatStyle, let date = input as? Date {
            dateStyle.calendar = calendar
            dateStyle.timeZone = timeZone
            return dateStyle.locale(locale).format(date)
        }
        if var verbatim = style as? Date.VerbatimFormatStyle, let date = input as? Date {
            verbatim.calendar = calendar
            verbatim.timeZone = timeZone
            return verbatim.locale(locale).format(date)
        }
        return style.locale(locale).format(input)
    }
}
