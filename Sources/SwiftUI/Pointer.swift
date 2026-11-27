import QtBridge

extension Context {
    func children<V: View>(of view: V, inside group: UnsafeMutableRawPointer,
                           focusForDescendants: Bool? = nil, prepare: ((CGSize) -> Void)? = nil) -> [Element] {
        var inner = descending(.position(0))
        inner.parent = group
        let elements: [Element]
        if let focusForDescendants {
            elements = view.resolveFocusChildren(in: inner, focused: focusForDescendants)
        } else {
            elements = view.resolve(inner)
        }
        let child = stacked(elements, axis: .vertical, alignment: .center, spacing: 8)
        return [child.grouped(in: group, prepare: prepare)]
    }
}

extension Element {
    func grouped(in widget: UnsafeMutableRawPointer, prepare: ((CGSize) -> Void)? = nil) -> Element {
        let useContent = sizesGroupToPositionedContent && prepare == nil
        let wrapper = wrapping(size: measure) { bounds, proposal in
            prepare?(bounds.size)
            qs_place(widget, bounds.minX, bounds.minY, bounds.width, bounds.height)
            self.place(CGRect(origin: .zero, size: bounds.size), proposal)
            qs_group_finish_layout(widget, useContent ? 1 : 0)
        }
        wrapper.sizesGroupToPositionedContent = useContent
        return wrapper
    }
}

extension View {
    public func contentShape<S: Shape>(_ shape: S, eoFill: Bool = false) -> some View {
        Transform(content: self) { view, ctx in
            let group = ctx.widget(QSGroup)
            return ctx.children(of: view, inside: group) { size in
                shape.displayPath(in: CGRect(origin: .zero, size: size), context: ctx).withNativePath {
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

    @_disfavoredOverload public func help<S: StringProtocol>(_ text: S) -> some View { environment(\.helpText, String(text)) }
    public func help(_ key: LocalizedStringKey) -> some View { help(Text(key)) }
    public func help(_ text: Text) -> some View {
        Transform(content: self) { view, context in
            view.resolve(context.with(\.helpText, text.resolvedString(context.environment.locale)))
        }
    }

    public func opacity(_ opacity: Double) -> some View {
        Transform(content: self) { view, ctx in
            let value = ctx.interpolated(opacity, key: "opacity")
            let inner = value <= 0 ? ctx.with(\.allowsHits, false) : ctx
            let group = inner.widget(QSGroup)
            qs_group_opacity(group, value)
            return inner.children(of: view, inside: group)
        }
    }
}
