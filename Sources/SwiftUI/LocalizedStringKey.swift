import Foundation

public struct LocalizedStringKey: Equatable, ExpressibleByStringInterpolation {
    fileprivate final class Argument: Equatable {
        let value: Any
        let matches: (Any) -> Bool
        let render: (String, Locale) -> String

        init<T: Equatable>(_ value: T, comparesValue: Bool = false, render: @escaping (String, Locale) -> String) {
            self.value = value
            matches = { comparesValue && ($0 as? T) == value }
            self.render = render
        }
        static func == (lhs: Argument, rhs: Argument) -> Bool { lhs === rhs || lhs.matches(rhs.value) }
    }

    private let key: String
    private let arguments: [Argument]
    public init(_ value: String) { key = value; arguments = [] }
    public init(stringLiteral value: String) { self.init(value) }
    public init(stringInterpolation: StringInterpolation) {
        key = stringInterpolation.key
        arguments = stringInterpolation.arguments
    }

    private struct Formatted<Input: Equatable, Style: Equatable>: Equatable {
        let value: Input
        let style: Style
    }

    public struct StringInterpolation: StringInterpolationProtocol {
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
            arguments.append(Argument(string) { _, _ in string })
        }
        public mutating func appendInterpolation(_ substring: Substring) { appendInterpolation(String(substring)) }
        public mutating func appendInterpolation<T: _FormatSpecifiable>(_ value: T) {
            appendInterpolation(value, specifier: value._specifier)
        }
        public mutating func appendInterpolation<T: _FormatSpecifiable>(_ value: T, specifier: String) {
            key += specifier
            arguments.append(Argument(value) { format, locale in
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
            key += "%@"
            arguments.append(Argument(subject) { _, _ in formatter?.string(for: subject) ?? String(describing: subject) })
        }
        public mutating func appendInterpolation<Subject: NSObject>(_ subject: Subject, formatter: Formatter? = nil) {
            key += "%@"
            arguments.append(Argument(subject) { _, _ in formatter?.string(for: subject) ?? String(describing: subject) })
        }
        public mutating func appendInterpolation<F: FormatStyle>(_ input: F.FormatInput, format: F)
        where F.FormatInput: Equatable, F.FormatOutput == String {
            key += "%@"
            arguments.append(Argument(Formatted(value: input, style: format), comparesValue: true) { _, locale in format.locale(locale).format(input) })
        }
        public mutating func appendInterpolation<F: FormatStyle>(_ input: F.FormatInput, format: F)
        where F.FormatInput: Equatable, F.FormatOutput == AttributedString {
            key += "%@"
            arguments.append(Argument(Formatted(value: input, style: format), comparesValue: true) { _, locale in
                String(format.locale(locale).format(input).characters)
            })
        }
        public mutating func appendInterpolation(_ text: Text) {
            key += "%@"
            arguments.append(Argument(text.string) { _, locale in text.resolvedString(locale) })
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

    func resolve(locale: Locale, table: String?, bundle: Bundle?) -> String {
        let format = localizedBundle(bundle ?? .main, locale: locale).localizedString(forKey: key, value: nil, table: table)
        guard !arguments.isEmpty else { return format }
        let template = format as NSString
        let matches = Self.placeholders.matches(in: format, range: NSRange(location: 0, length: template.length))
        var result = "", cursor = 0, next = 0
        for match in matches {
            let range = match.range
            result += template.substring(with: NSRange(location: cursor, length: range.location - cursor))
            cursor = NSMaxRange(range)
            let conversion = match.range(at: 2)
            guard conversion.location != NSNotFound else { result += "%"; continue }
            let position = match.range(at: 1)
            let index: Int
            if position.location == NSNotFound {
                index = next
                next += 1
            } else {
                index = (Int(template.substring(with: position)) ?? 0) - 1
            }
            if arguments.indices.contains(index) {
                result += arguments[index].render("%" + template.substring(with: conversion), locale)
            } else {
                result += template.substring(with: range)
            }
        }
        return result + template.substring(from: cursor)
    }
}
