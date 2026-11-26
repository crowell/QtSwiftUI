import QtBridge

extension Context {
    func children<V: View>(of view: V, inside group: UnsafeMutableRawPointer) -> [Element] {
        var inner = descending(.position(0))
        inner.parent = group
        let child = stacked(view.resolve(inner), axis: .vertical, alignment: .center, spacing: 8)
        let wrapper = Element(size: child.measure) { bounds, proposal in
            qs_place(group, bounds.minX, bounds.minY, bounds.width, bounds.height)
            child.place(CGRect(origin: .zero, size: bounds.size), proposal)
        }
        wrapper.values = child.values
        wrapper.priority = child.priority
        return [wrapper]
    }
}

extension View {
    public func onHover(perform action: @escaping (Bool) -> Void) -> some View {
        Transform(content: self) { view, ctx in
            let group = ctx.widget(QSGroup, hover: action)
            qs_group_hover(group, 1)
            return ctx.children(of: view, inside: group)
        }
    }

    public func help<S: StringProtocol>(_ text: S) -> some View { environment(\.helpText, String(text)) }
    public func help(_ text: Text) -> some View { help(text.string) }

    public func opacity(_ opacity: Double) -> some View {
        Transform(content: self) { view, ctx in
            let group = ctx.widget(QSGroup)
            qs_group_opacity(group, ctx.interpolated(opacity, key: "opacity"))
            return ctx.children(of: view, inside: group)
        }
    }
}
