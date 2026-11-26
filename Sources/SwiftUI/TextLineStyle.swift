extension Text {
    public struct LineStyle: Hashable, Sendable {
        let pattern: Pattern
        let color: Color?

        public init(pattern: Pattern = .solid, color: Color? = nil) {
            self.pattern = pattern
            self.color = color
        }

        public struct Pattern: Hashable, Sendable {
            let qt: Int32
            public static let solid = Self(qt: 1)
            public static let dash = Self(qt: 2)
            public static let dot = Self(qt: 3)
            public static let dashDot = Self(qt: 4)
            public static let dashDotDot = Self(qt: 5)
        }

        public static let single = Self()
    }

    nonisolated public func underline(_ isActive: Bool = true, color: Color? = nil) -> Text {
        underline(isActive, pattern: .solid, color: color)
    }

    nonisolated public func underline(_ isActive: Bool = true, pattern: LineStyle.Pattern, color: Color? = nil) -> Text {
        var copy = self
        copy.underlineOverride = isActive ? .enabled(.init(pattern: pattern, color: color)) : .disabled
        return copy
    }

    nonisolated public func strikethrough(_ isActive: Bool = true, color: Color? = nil) -> Text {
        strikethrough(isActive, pattern: .solid, color: color)
    }

    nonisolated public func strikethrough(_ isActive: Bool = true, pattern: LineStyle.Pattern, color: Color? = nil) -> Text {
        var copy = self
        copy.strikethroughOverride = isActive ? .enabled(.init(pattern: pattern, color: color)) : .disabled
        return copy
    }
}

enum TextLineDecoration: Sendable {
    case enabled(Text.LineStyle), disabled

    func resolve(_ style: Text.LineStyle?) -> Text.LineStyle? {
        switch self {
        case .disabled: nil
        case .enabled(let inherited): style ?? inherited
        }
    }
}

nonisolated private struct DecoratedTextView<Content: View>: View {
    let content: Content
    let style: TextLineDecoration
    let strike: Bool
    @MainActor var body: some View {
        content.environment(strike ? \.textStrikethrough : \.textUnderline, style)
    }
}

extension View {
    nonisolated public func underline(_ isActive: Bool = true, pattern: Text.LineStyle.Pattern = .solid, color: Color? = nil) -> some View {
        DecoratedTextView(content: self, style: isActive ? .enabled(.init(pattern: pattern, color: color)) : .disabled, strike: false)
    }

    nonisolated public func strikethrough(_ isActive: Bool = true, pattern: Text.LineStyle.Pattern = .solid, color: Color? = nil) -> some View {
        DecoratedTextView(content: self, style: isActive ? .enabled(.init(pattern: pattern, color: color)) : .disabled, strike: true)
    }
}
