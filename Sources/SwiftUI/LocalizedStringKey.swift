import Foundation

public struct LocalizedStringKey: Equatable, ExpressibleByStringInterpolation {
    public typealias StringLiteralType = String
    public typealias ExtendedGraphemeClusterLiteralType = String
    public typealias UnicodeScalarLiteralType = String

    fileprivate final class Argument: Equatable {
        let value: Any
        let matches: ((Any) -> Bool)?
        let attributed: Bool
        let render: (String, EnvironmentValues) -> TextContent

        init(_ value: Any, matching: ((Any) -> Bool)? = nil, attributed: Bool,
             content: @escaping (String, EnvironmentValues) -> TextContent) {
            self.value = value
            matches = matching
            self.attributed = attributed
            render = content
        }

        convenience init<T: Equatable>(_ value: T, comparesValue: Bool, attributed: Bool,
                                       content: @escaping (String, EnvironmentValues) -> TextContent) {
            self.init(value, matching: comparesValue ? { ($0 as? T) == value } : nil, attributed: attributed, content: content)
        }

        convenience init<T: Equatable>(_ value: T, comparesValue: Bool = false, render: @escaping (String, Locale) -> String) {
            self.init(value, comparesValue: comparesValue, attributed: false) { specifier, environment in
                .plain(render(specifier, environment.locale))
            }
        }
        static func == (lhs: Argument, rhs: Argument) -> Bool {
            if lhs === rhs { return true }
            guard let matches = lhs.matches, rhs.matches != nil else { return false }
            return matches(rhs.value)
        }
    }

    private let key: String
    private let arguments: [Argument]
    var usesAttributedText: Bool { arguments.contains(where: \.attributed) }
    public init(_ value: String) { key = value; arguments = [] }
    public init(stringLiteral value: String) { self.init(value) }
    public init(stringInterpolation: StringInterpolation) {
        key = stringInterpolation.key
        arguments = stringInterpolation.arguments
    }

    public static func == (a: LocalizedStringKey, b: LocalizedStringKey) -> Bool {
        a.key == b.key && a.arguments == b.arguments
    }

    private struct Formatted<Input: Equatable, Style: Equatable>: Equatable {
        let value: Input
        let style: Style
    }

    public struct StringInterpolation: StringInterpolationProtocol {
        public typealias StringLiteralType = String
        fileprivate var key = ""
        fileprivate var arguments: [Argument] = []
        public init(literalCapacity: Int, interpolationCount: Int) {
            key.reserveCapacity(literalCapacity)
            arguments.reserveCapacity(interpolationCount)
        }
        public mutating func appendLiteral(_ literal: String) {
            key += literal.replacingOccurrences(of: "%", with: "%%")
        }
        public mutating func appendInterpolation(_ string: String) {
            key += "%@"
            arguments.append(Argument(string, comparesValue: true) { _, _ in string })
        }
        public mutating func appendInterpolation(_ substring: Substring) { appendInterpolation(String(substring)) }
        public mutating func appendInterpolation<T: _FormatSpecifiable>(_ value: T) {
            appendInterpolation(value, specifier: value._specifier)
        }
        public mutating func appendInterpolation<T: _FormatSpecifiable>(_ value: T, specifier: String) {
            key += specifier
            arguments.append(Argument(value, comparesValue: true) { format, locale in
                // Pass only a single, type-compatible conversion to Foundation. Translated
                // positional markers are resolved before this point.
                let floats = "fFeEgGaA"
                let integers = "diuoxX"
                let kind = value._specifier.last
                let conversion = format.last
                if let kind, let conversion,
                   (floats.contains(kind) && floats.contains(conversion)) ||
                    (integers.contains(kind) && integers.contains(conversion)) {
                    return String(format: format, locale: locale, arguments: [value._arg])
                }
                return String(describing: value)
            })
        }
        public mutating func appendInterpolation<Subject: ReferenceConvertible>(_ subject: Subject, formatter: Formatter? = nil) {
            appendSubject(subject, formatter: formatter)
        }
        public mutating func appendInterpolation<Subject: NSObject>(_ subject: Subject, formatter: Formatter? = nil) {
            appendSubject(subject, formatter: formatter)
        }
        private mutating func appendSubject<Subject: Equatable>(_ subject: Subject, formatter: Formatter?) {
            key += "%@"
            if let formatter {
                let source = TextSource.formatted(subject, using: formatter)
                arguments.append(Argument(subject, attributed: false) { _, environment in source.resolve(in: environment) })
            } else {
                arguments.append(Argument(subject) { _, _ in String(describing: subject) })
            }
        }
        public mutating func appendInterpolation<F: FormatStyle>(_ input: F.FormatInput, format: F)
        where F.FormatInput: Equatable, F.FormatOutput == String {
            key += "%@"
            arguments.append(Argument(Formatted(value: input, style: format), comparesValue: true, attributed: false) { _, environment in
                .plain(environment.format(input, with: format))
            })
        }
        public mutating func appendInterpolation<F: FormatStyle>(_ input: F.FormatInput, format: F)
        where F.FormatInput: Equatable, F.FormatOutput == AttributedString {
            key += "%@"
            arguments.append(Argument(Formatted(value: input, style: format), comparesValue: true, attributed: true) { _, environment in
                .attributed(format.locale(environment.locale).format(input))
            })
        }
        public mutating func appendInterpolation(_ text: Text) {
            key += "%@"
            arguments.append(Argument(text, attributed: text.source.usesAttributedText) { _, environment in
                text.source.resolve(in: environment)
            })
        }
        public mutating func appendInterpolation(_ attributedString: AttributedString) {
            key += "%@"
            arguments.append(Argument(attributedString, comparesValue: true, attributed: true) { _, _ in .attributed(attributedString) })
        }
        public mutating func appendInterpolation(_ attributedSubstring: AttributedSubstring) {
            appendInterpolation(AttributedString(attributedSubstring))
        }
        @_disfavoredOverload public mutating func appendInterpolation<T>(_ object: T) {
            appendInterpolation(String(describing: object))
        }
    }

    private static let placeholders = try! NSRegularExpression(
        pattern: #"%%|%(?:(\d+)\$)?([-+ #0']*\d{0,3}(?:\.\d{0,3})?(?:hh|ll|[hljztL])?[diuoxXfFeEgGaA@])"#)

    private func localizedBundle(_ bundle: Bundle, locale: Locale) -> Bundle {
        let localizations = bundle.localizations
        guard !localizations.isEmpty else { return bundle }
        // Corelibs Foundation can return the process language even for an explicit
        // locale preference. Match the locale and its parent language bundles first.
        func normalized(_ identifier: String) -> String {
            identifier.replacingOccurrences(of: "_", with: "-").lowercased()
        }
        var identifiers = [locale.identifier, locale.language.maximalIdentifier]
        if let language = locale.language.languageCode?.identifier {
            if let script = locale.language.script?.identifier { identifiers.append(language + "-" + script) }
            identifiers.append(language)
        }
        let match = identifiers.lazy.compactMap { wanted in
            localizations.first { normalized($0) == normalized(wanted) }
        }.first
        guard let language = match, let url = bundle.url(forResource: language, withExtension: "lproj") else { return bundle }
        return Bundle(url: url) ?? bundle
    }

    func resolve(in environment: EnvironmentValues, table: String?, bundle: Bundle?) -> TextContent {
        let format = localizedBundle(bundle ?? .main, locale: environment.locale).localizedString(forKey: key, value: nil, table: table)
        guard !arguments.isEmpty else { return .plain(format) }
        let template = format as NSString
        let matches = Self.placeholders.matches(in: format, range: NSRange(location: 0, length: template.length))
        var result = TextContent.plain("")
        var cursor = 0, next = 0
        for match in matches {
            let range = match.range
            result.append(.plain(template.substring(with: NSRange(location: cursor, length: range.location - cursor))))
            cursor = NSMaxRange(range)
            let conversion = match.range(at: 2)
            guard conversion.location != NSNotFound else { result.append(.plain("%")); continue }
            let position = match.range(at: 1)
            let index: Int
            if position.location == NSNotFound {
                index = next
                next += 1
            } else {
                index = (Int(template.substring(with: position)) ?? 0) - 1
            }
            if arguments.indices.contains(index) {
                result.append(arguments[index].render("%" + template.substring(with: conversion), environment))
            } else {
                result.append(.plain(template.substring(with: range)))
            }
        }
        result.append(.plain(template.substring(from: cursor)))
        return result
    }
}
