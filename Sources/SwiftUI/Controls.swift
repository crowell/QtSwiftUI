import QtBridge

extension Context {
    func style(_ widget: UnsafeMutableRawPointer) {
        let font = environment.font ?? .body
        let alignment = environment.multilineTextAlignment
        qs_style(widget, font.qtFamily, font.size, font.weight.value, font.slanted ? 1 : 0, environment.tracking, environment.foreground.hex(environment.colorScheme),
                 alignment == .leading ? -1 : alignment == .center ? 0 : 1, environment.lineLimit == 1 ? 0 : 1)
    }
    func control(_ widget: UnsafeMutableRawPointer, expands: Bool = false) -> Element {
        style(widget)
        return Element { p in
            let hint = qs_measure(widget, p.width ?? -1)
            return CGSize(width: expands ? (p.width ?? hint.width) : hint.width, height: hint.height)
        } place: { rect, _ in qs_place(widget, rect.minX, rect.minY, rect.width, rect.height) }
    }
}
public struct Text: Primitive {
    var string: String
    private var attributes: [(inout EnvironmentValues) -> Void] = []
    public nonisolated init<S: StringProtocol>(_ content: S) { string = String(content) }
    public nonisolated init(verbatim content: String) { string = content }
    public func font(_ font: Font?) -> Text { modified { $0.font = font } }
    public func fontWeight(_ weight: Font.Weight?) -> Text { modified { $0.font = ($0.font ?? .body).weight(weight ?? .regular) } }
    public func bold(_ active: Bool = true) -> Text { modified { if active { $0.font = ($0.font ?? .body).bold() } } }
    public func italic(_ active: Bool = true) -> Text { modified { if active { $0.font = ($0.font ?? .body).italic() } } }
    public func foregroundColor(_ color: Color?) -> Text { modified { $0.foreground = color ?? .primary } }
    private func modified(_ change: @escaping (inout EnvironmentValues) -> Void) -> Self {
        var copy = self; copy.attributes.append(change); return copy
    }
    func styled(_ context: Context) -> Context {
        var ctx = context
        for attribute in attributes { attribute(&ctx.environment) }
        return ctx
    }
    func elements(in context: Context) -> [Element] {
        let ctx = styled(context)
        let widget = ctx.widget(QSLabel)
        qs_selectable(widget, ctx.environment.selectableText ? 1 : 0)
        qs_text(widget, string)
        ctx.style(widget)
        return [Element { p in
            let hint = qs_measure(widget, p.width ?? -1)
            let font = ctx.environment.font ?? .body
            let height = ctx.environment.lineLimit.map { min(hint.height, CGFloat($0) * ceil(font.size * 1.25)) } ?? hint.height
            return CGSize(width: hint.width, height: height)
        } place: { rect, _ in qs_place(widget, rect.minX, rect.minY, rect.width, rect.height) }]
    }
}
public struct Button<Label: View>: Primitive {
    let action: () -> Void, label: Label
    public init(action: @escaping () -> Void, @ViewBuilder label: () -> Label) { self.action = action; self.label = label() }
    public init<S: StringProtocol>(_ title: S, action: @escaping () -> Void) where Label == Text {
        self.init(action: action) { Text(title) }
    }
    func elements(in context: Context) -> [Element] {
        let style = context.environment.buttonStyle
        let widget = context.widget(context.environment.isLink ? QSLink : QSButton, pressed: { [weak host = context.host] _ in
            if style != nil { host?.update() }
        }, action: { _ in action() })
        qs_plain_button(widget, style != nil ? 1 : 0)
        if style == nil, let text = label as? Text {
            qs_text(widget, text.string)
            return [text.styled(context).control(widget)]
        }
        var ctx = context
        ctx.parent = widget
        ctx.environment.identifier = ""
        ctx.environment.isLink = false
        ctx.environment.focus = nil
        let configured = style?(.init(label: .init(content: AnyView(label)), isPressed: qs_button_down(widget) != 0))
        let child = stacked((configured ?? AnyView(label)).resolve(ctx.descending(.position(0))), axis: .horizontal, alignment: .center, spacing: 4)
        let dx: CGFloat = style == nil ? 8 : 0, dy: CGFloat = style == nil ? 5 : 0
        func inner(_ p: ProposedViewSize) -> ProposedViewSize {
            .init(width: p.width.map { max(0, $0 - 2 * dx) }, height: p.height.map { max(0, $0 - 2 * dy) })
        }
        return [Element { p in
            let size = child.measure(inner(p))
            return CGSize(width: size.width + 2 * dx, height: size.height + 2 * dy)
        } place: { rect, p in
            qs_place(widget, rect.minX, rect.minY, rect.width, rect.height)
            child.place(.init(origin: CGPoint(x: dx, y: dy), size: child.measure(inner(p))), inner(p))
        }]
    }
}
public struct Toggle<Label: View>: Primitive {
    let isOn: Binding<Bool>, label: Label
    public init(isOn: Binding<Bool>, @ViewBuilder label: () -> Label) { self.isOn = isOn; self.label = label() }
    public init<S: StringProtocol>(_ title: S, isOn: Binding<Bool>) where Label == Text {
        self.init(isOn: isOn) { Text(title) }
    }
    func elements(in context: Context) -> [Element] {
        let widget = context.widget(QSToggle, action: { isOn.wrappedValue = $0 == "1" })
        qs_checked(widget, isOn.wrappedValue ? 1 : 0)
        if let text = label as? Text {
            qs_text(widget, text.string)
            return [text.styled(context).control(widget)]
        }
        return [stacked([context.control(widget)] + label.resolve(context.descending(.position(0))), axis: .horizontal, alignment: .center, spacing: 4)]
    }
}
@MainActor private func field(_ title: String, text: Binding<String>, secure: Bool, in context: Context) -> Element {
    let widget = context.widget(secure ? QSSecureEdit : QSEdit, action: { text.wrappedValue = $0 })
    qs_text(widget, text.wrappedValue)
    qs_hint(widget, title)
    return context.control(widget, expands: true)
}
public struct TextField<Label: View>: Primitive {
    let title: String, text: Binding<String>
    public init<S: StringProtocol>(_ title: S, text: Binding<String>) where Label == Text { self.title = String(title); self.text = text }
    func elements(in context: Context) -> [Element] { [field(title, text: text, secure: false, in: context)] }
}
public struct SecureField<Label: View>: Primitive {
    let title: String, text: Binding<String>
    public init<S: StringProtocol>(_ title: S, text: Binding<String>) where Label == Text { self.title = String(title); self.text = text }
    func elements(in context: Context) -> [Element] { [field(title, text: text, secure: true, in: context)] }
}
public struct Slider<Label: View, ValueLabel: View>: Primitive {
    let fraction: () -> Double, move: (Double) -> Void
    public init<V: BinaryFloatingPoint>(value: Binding<V>, in bounds: ClosedRange<V> = 0...1, step: V.Stride? = nil)
    where Label == EmptyView, ValueLabel == EmptyView, V.Stride: BinaryFloatingPoint {
        let start = Double(bounds.lowerBound), length = Double(bounds.upperBound) - start
        fraction = { length > 0 ? (Double(value.wrappedValue) - start) / length : 0 }
        let interval: Double
        if let step { interval = Double(step) } else { interval = 0 }
        move = { t in
            let offset = interval > 0 ? (t * length / interval).rounded() * interval : t * length
            value.wrappedValue = V(start + min(length, max(0, offset)))
        }
    }
    func elements(in context: Context) -> [Element] {
        let widget = context.widget(QSSlider, action: { if let n = Double($0) { move(n) } })
        qs_value(widget, fraction())
        return [context.control(widget, expands: true)]
    }
}
public struct ProgressView<Label: View, CurrentValueLabel: View>: Primitive {
    let fraction: Double?
    public init() where Label == EmptyView, CurrentValueLabel == EmptyView { fraction = nil }
    public init<V: BinaryFloatingPoint>(value: V?, total: V = 1) where Label == EmptyView, CurrentValueLabel == EmptyView {
        fraction = value.map { total > 0 ? min(1, max(0, Double($0 / total))) : 0 }
    }
    func elements(in context: Context) -> [Element] {
        let widget = context.widget(QSProgress)
        qs_value(widget, fraction ?? -1)
        return [context.control(widget, expands: true)]
    }
}
public struct ScrollView<Content: View>: Primitive {
    public var axes: Axis.Set, showsIndicators: Bool, content: Content
    public init(_ axes: Axis.Set = .vertical, showsIndicators: Bool = true, @ViewBuilder content: () -> Content) {
        self.axes = axes; self.showsIndicators = showsIndicators; self.content = content()
    }
    func elements(in context: Context) -> [Element] {
        let widget = context.widget(QSScroll)
        var inner = context.descending(.position(0))
        inner.parent = qs_scroll_content(widget)
        let view = stacked(content.resolve(inner), axis: .vertical, alignment: .center, spacing: 8)
        let horizontal = axes.contains(.horizontal), vertical = axes.contains(.vertical)
        qs_scroll_axes(widget, showsIndicators && horizontal && context.environment.horizontalScrollIndicatorVisibility.showsBar ? 1 : 0,
                       showsIndicators && vertical && context.environment.verticalScrollIndicatorVisibility.showsBar ? 1 : 0)
        func offer(_ p: ProposedViewSize) -> ProposedViewSize { .init(width: horizontal ? nil : p.width, height: vertical ? nil : p.height) }
        return [Element { p in
            let ideal = view.measure(offer(p))
            return CGSize(width: p.width ?? ideal.width, height: p.height ?? ideal.height)
        } place: { bounds, _ in
            qs_place(widget, bounds.minX, bounds.minY, bounds.width, bounds.height)
            let proposal = offer(ProposedViewSize(bounds.size))
            let size = view.measure(proposal)
            let contentSize = CGSize(width: max(bounds.width, size.width), height: max(bounds.height, size.height))
            qs_scroll_size(widget, Int32(contentSize.width.rounded(.up)), Int32(contentSize.height.rounded(.up)))
            view.place(Alignment.top.rect(size, in: CGRect(origin: .zero, size: contentSize)), proposal)
        }]
    }
}
