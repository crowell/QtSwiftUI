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
}

enum TextUnderline: Sendable {
    case enabled(Text.LineStyle), disabled
}

nonisolated private struct UnderlinedView<Content: View>: View {
    let content: Content
    let underline: TextUnderline
    @MainActor var body: some View { content.environment(\.textUnderline, underline) }
}

extension View {
    nonisolated public func underline(_ isActive: Bool = true, pattern: Text.LineStyle.Pattern = .solid, color: Color? = nil) -> some View {
        UnderlinedView(content: self, underline: isActive ? .enabled(.init(pattern: pattern, color: color)) : .disabled)
    }
}
