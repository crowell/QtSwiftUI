import QtBridge

public struct PointerStyle: Sendable {
    fileprivate let cursor: QSPointer
    public static let `default` = Self(cursor: QSPointerArrow)
    public static let horizontalText = Self(cursor: QSPointerText)
    public static let rectSelection = Self(cursor: QSPointerCross)
    public static let grabIdle = Self(cursor: QSPointerOpenHand)
    public static let grabActive = Self(cursor: QSPointerClosedHand)
    public static let link = Self(cursor: QSPointerLink)
    public static let columnResize = Self(cursor: QSPointerColumn)
    public static let rowResize = Self(cursor: QSPointerRow)
}

extension View {
    nonisolated public func pointerStyle(_ style: PointerStyle?) -> some View {
        Transform(content: self) { view, context in
            let group = context.widget(QSGroup)
            qs_pointer_style(group, style?.cursor ?? QSPointerAutomatic)
            return context.children(of: view, inside: group)
        }
    }
}
