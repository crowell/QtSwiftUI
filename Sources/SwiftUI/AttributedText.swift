import Foundation
import QtBridge

extension AttributeScopes {
    public var swiftUI: SwiftUIAttributes.Type { SwiftUIAttributes.self }
    public struct SwiftUIAttributes: AttributeScope {
        public let font: FontAttribute
        public let foregroundColor: ForegroundColorAttribute
        public let underlineStyle: UnderlineStyleAttribute
        public let backgroundColor: BackgroundColorAttribute
        public let foundation: FoundationAttributes

        public enum UnderlineStyleAttribute: AttributedStringKey {
            public typealias Value = Text.LineStyle
            public static let name = "SwiftUI.UnderlineStyle"
        }
        public enum FontAttribute: AttributedStringKey {
            public typealias Value = Font
            public static let name = "SwiftUI.Font"
        }
        public enum ForegroundColorAttribute: AttributedStringKey {
            public typealias Value = Color
            public static let name = "SwiftUI.ForegroundColor"
        }
        public enum BackgroundColorAttribute: AttributedStringKey {
            public typealias Value = Color
            public static let name = "SwiftUI.BackgroundColor"
        }
    }
}

extension AttributeDynamicLookup {
    public subscript<T: AttributedStringKey>(dynamicMember keyPath: KeyPath<AttributeScopes.SwiftUIAttributes, T>) -> T { self[T.self] }
}

extension Text {
    func configure(_ text: AttributedString, on widget: UnsafeMutableRawPointer, in environment: EnvironmentValues) {
        qs_attributed_begin(widget)
        for run in text.runs {
            let value = String(text[run.range].characters)
            let font = run.font
            let underline: Text.LineStyle?
            switch underlineOverride ?? environment.textUnderline {
            case .disabled: underline = nil
            case .enabled(let inherited): underline = run.underlineStyle ?? inherited
            case nil: underline = run.underlineStyle
            }
            value.withCString { bytes in
                qs_attributed_append(widget, bytes, value.utf8.count, run.link?.absoluteString ?? "",
                                     run.foregroundColor?.hex(environment.colorScheme) ?? "",
                                     run.backgroundColor?.hex(environment.colorScheme) ?? "",
                                     font?.qtFamily ?? "", Double(font?.size ?? 0), font?.qtWeight ?? 400, font?.slanted == true ? 1 : 0,
                                     underline?.pattern.qt ?? 0, underline?.color?.hex(environment.colorScheme) ?? "")
            }
        }
        qs_attributed_finish(widget, environment.selectableText ? 1 : 0)
    }
}
