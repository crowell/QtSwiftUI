import QtBridge

extension Context {
    func children<V: View>(of view: V, inside group: UnsafeMutableRawPointer,
                           prepare: ((CGSize) -> Void)? = nil) -> [Element] {
        var inner = descending(.position(0))
        inner.parent = group
        let child = stacked(view.resolve(inner), axis: .vertical, alignment: .center, spacing: 8)
        let wrapper = child.wrapping(size: child.measure) { bounds, proposal in
            prepare?(bounds.size)
            qs_place(group, bounds.minX, bounds.minY, bounds.width, bounds.height)
            child.place(CGRect(origin: .zero, size: bounds.size), proposal)
            qs_group_finish_layout(group)
        }
        return [wrapper]
    }
}

extension View {
    public func contentShape<S: Shape>(_ shape: S, eoFill: Bool = false) -> some View {
        Transform(content: self) { view, ctx in
            let group = ctx.widget(QSGroup)
            return ctx.children(of: view, inside: group) { size in
                shape.path(in: CGRect(origin: .zero, size: size)).withNativePath {
                    qs_group_shape(group, $0, eoFill ? 1 : 0)
                }
            }
        }
    }
    public func onTapGesture(count: Int = 1, perform action: @escaping () -> Void) -> some View {
        gesture(TapGesture(count: count).onEnded(action))
    }
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
