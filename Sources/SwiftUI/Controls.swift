import QtBridge

extension Context {
    func style(_ widget: UnsafeMutableRawPointer) {
        let font = environment.font ?? .body
        let alignment = environment.multilineTextAlignment
        let leading: Int32 = environment.layoutDirection == .rightToLeft ? 1 : -1
        qs_style(widget, font.qtFamily, font.size, font.qtWeight, font.slanted ? 1 : 0, environment.tracking, environment.foreground.hex(environment.colorScheme),
                 alignment == .leading ? leading : alignment == .center ? 0 : -leading, environment.lineLimit == 1 ? 0 : 1)
        if case .linear(let gradient) = environment.foregroundPaint {
            gradient.gradient.stops(for: environment.colorScheme).withUnsafeBufferPointer { stops in
                let start = gradient.startPoint, end = gradient.endPoint
                qs_text_gradient(widget, leading > 0 ? 1 - start.x : start.x, start.y,
                                 leading > 0 ? 1 - end.x : end.x, end.y, stops.baseAddress, stops.count)
            }
        }
    }
    func styleControl(_ widget: UnsafeMutableRawPointer) {
        let scale = environment.controlSize.qtScale
        if environment.font == nil && scale != 1 {
            with(\.font, .system(size: Font.body.size * scale)).style(widget)
        } else { style(widget) }
        qs_control_scale(widget, scale)
    }
    func control(_ widget: UnsafeMutableRawPointer, expands: Bool = false) -> Element {
        styleControl(widget)
        return Element { p in
            let hint = qs_measure(widget, p.width ?? -1)
            return CGSize(width: expands ? (p.width ?? hint.width) : hint.width, height: hint.height)
        } place: { rect, _ in qs_place(widget, rect.minX, rect.minY, rect.width, rect.height) }
    }
}
public nonisolated struct Text: Primitive {
    private var literal = ""
    private var localized: (key: LocalizedStringKey, table: String?, bundle: Bundle?)?
    var string: String { resolvedString(.autoupdatingCurrent) }
    func resolvedString(_ locale: Locale) -> String {
        guard let localized else { return literal }
        return localized.key.resolve(locale: locale, table: localized.table, bundle: localized.bundle)
    }
    public init(_ key: LocalizedStringKey, tableName: String? = nil, bundle: Bundle? = nil, comment: StaticString? = nil) {
        localized = (key, tableName, bundle)
    }
    nonisolated var underlineOverride: TextLineDecoration?
    nonisolated var strikethroughOverride: TextLineDecoration?
    nonisolated private(set) var attributed: AttributedString?
    @_disfavoredOverload public nonisolated init(_ attributedContent: AttributedString) {
        literal = String(attributedContent.characters)
        attributed = attributedContent
    }
    private(set) var foregroundOverride: AnyShapeStyle?
    private var attributes: [(inout EnvironmentValues) -> Void] = []
    @_disfavoredOverload public nonisolated init<S: StringProtocol>(_ content: S) { literal = String(content) }
    public nonisolated init(verbatim content: String) { literal = content }
    public func font(_ font: Font?) -> Text { modified { $0.font = font } }
    public func accessibilityLabel(_ label: Text) -> Text {
        modified { environment in environment.label = label.resolvedString(environment.locale) }
    }
    public func accessibilityLabel(_ labelKey: LocalizedStringKey) -> Text { accessibilityLabel(Text(labelKey)) }
    @_disfavoredOverload public func accessibilityLabel<S: StringProtocol>(_ label: S) -> Text { accessibilityLabel(Text(label)) }
    public func kerning(_ kerning: CGFloat) -> Text { modified { $0.kerning = kerning } }
    public func tracking(_ tracking: CGFloat) -> Text { modified { $0.tracking = tracking } }
    public func fontWeight(_ weight: Font.Weight?) -> Text { modified { $0.font = ($0.font ?? .body).weight(weight ?? .regular) } }
    public func bold(_ active: Bool = true) -> Text { modified { if active { $0.font = ($0.font ?? .body).bold() } } }
    public func italic(_ active: Bool = true) -> Text { modified { if active { $0.font = ($0.font ?? .body).italic() } } }
    public func foregroundColor(_ color: Color?) -> Text {
        var copy = self
        copy.foregroundOverride = color.map(AnyShapeStyle.init)
        return copy
    }
    public func foregroundStyle<S: ShapeStyle>(_ style: S) -> Text {
        var copy = self
        copy.foregroundOverride = AnyShapeStyle(style)
        return copy
    }
    private func modified(_ change: @escaping (inout EnvironmentValues) -> Void) -> Self {
        var copy = self; copy.attributes.append(change); return copy
    }
    func styledEnvironment(_ environment: EnvironmentValues) -> EnvironmentValues {
        var result = environment
        for attribute in attributes { attribute(&result) }
        if let foregroundOverride { result.foregroundPaint = foregroundOverride.resolvedPaint(in: result) }
        return result
    }
    @MainActor func styled(_ context: Context) -> Context {
        var ctx = context
        ctx.environment = styledEnvironment(ctx.environment)
        return ctx
    }
    @MainActor func elements(in context: Context) -> [Element] {
        if let reader = context.fieldLabelReader {
            return [Element { _ in .zero } place: { _, _ in
                if reader.first == nil { reader.first = (self, context.environment.locale) }
            }]
        }
        if context.environment.accessibilityTraits.contains(.isLink) {
            let group = context.widget(QSGroup)
            qs_group(group, 2, 0, 0, context.environment.accessibleValue)
            var child = context
            child.environment.accessibilityTraits.remove(.isLink)
            child.environment.identifier = ""
            return child.children(of: self, inside: group)
        }
        let ctx = styled(context)
        let string = resolvedString(ctx.environment.locale)
        let widget: UnsafeMutableRawPointer
        let spacing = ctx.environment.lineSpacing.isFinite ? max(0, ctx.environment.lineSpacing) : 0
        let richLayout = (underlineOverride ?? ctx.environment.textUnderline) != nil
            || (strikethroughOverride ?? ctx.environment.textStrikethrough) != nil || spacing > 0
        if let attributed = attributed ?? (richLayout ? AttributedString(string) : nil) {
            widget = ctx.widget(QSAttributedLabel, action: { value in
                if let link = URL(string: value) { ctx.environment.openURL(link) }
            })
            ctx.style(widget)
            configure(attributed, on: widget, in: ctx.environment)
        } else {
            widget = ctx.widget(QSLabel)
            qs_selectable(widget, ctx.environment.selectableText ? 1 : 0)
            qs_text(widget, string)
            ctx.style(widget)
        }
        let limit = Int32(clamping: ctx.environment.lineLimit.map { max(1, $0) } ?? 0)
        let mode = ctx.environment.truncationMode.nativeMode
        let element = Element { p in
            let hint = qs_measure_text(widget, p.width ?? -1, limit, mode)
            let line = qs_line_height(widget)
            let minimum = ctx.environment.minimumLines
            func heightForLines(_ count: Int) -> CGFloat {
                CGFloat(max(1, count)) * line + CGFloat(max(0, count - 1)) * spacing
            }
            let capped = ctx.environment.lineLimit.map { min(hint.height, heightForLines($0)) } ?? hint.height
            let height = minimum > 1 ? max(capped, CGFloat(minimum) * line) : capped
            return CGSize(width: hint.width, height: height)
        } place: { rect, _ in
            qs_place(widget, rect.minX, rect.minY, rect.width, rect.height)
            qs_text_display(widget, limit, mode, ctx.environment.label.isEmpty ? 1 : 0)
        }
        element.baselines = { _, size in
            let result = qs_text_baselines(widget, size.width, size.height)
            return TextBaselines(first: result.first, last: result.last)
        }
        return [element]
    }
}
public struct Button<Label: View>: Primitive {
    let action: () -> Void, label: Label
    public init(action: @escaping () -> Void, @ViewBuilder label: () -> Label) { self.action = action; self.label = label() }
    public init(_ titleKey: LocalizedStringKey, action: @escaping () -> Void) where Label == Text {
        self.init(action: action) { Text(titleKey) }
    }
    @_disfavoredOverload public init<S: StringProtocol>(_ title: S, action: @escaping () -> Void) where Label == Text {
        self.init(action: action) { Text(title) }
    }
    func elements(in context: Context) -> [Element] {
        buttonElements(in: context, kind: context.environment.isLink ? QSLink : QSButton, activate: { _ in action() })
    }

    func buttonElements(in context: Context, kind: QSKind, activate: @escaping (String) -> Void,
                        configure: (UnsafeMutableRawPointer) -> Void = { _ in }) -> [Element] {
        if context.fieldLabelReader != nil { return label.resolve(context) }
        let style = context.environment.buttonStyle
        let widget = context.widget(kind, pressed: { [weak host = context.host] _ in
            if style != nil { host?.update() }
        }, action: activate)
        configure(widget)
        context.installShortcut(on: widget)
        qs_plain_button(widget, style != nil ? 1 : 0)
        if style == nil, let text = label as? Text, text.attributed == nil, text.underlineOverride == nil, context.environment.textUnderline == nil,
           text.strikethroughOverride == nil, context.environment.textStrikethrough == nil {
            qs_text(widget, text.resolvedString(context.environment.locale))
            return [text.styled(context).control(widget)]
        }
        var ctx = context
        ctx.parent = widget
        ctx.environment.identifier = ""
        ctx.environment.isLink = false
        ctx.environment.accessibilityTraits.remove(.isLink)
        ctx.environment.focus = nil
        ctx.environment.isFocused = qs_widget_has_focus(widget) != 0
        let configured = style?(.init(label: .init(content: AnyView(label)), isPressed: qs_button_down(widget) != 0), ctx)
        let child = stacked((configured ?? AnyView(label)).resolve(ctx.descending(.position(0))), axis: .horizontal, alignment: .center, spacing: 4, direction: ctx.environment.layoutDirection)
        let scale = context.environment.controlSize.qtScale
        let dx: CGFloat = style == nil ? 8 * scale : 0, dy: CGFloat = style == nil ? 5 * scale : 0
        let indicator = kind == QSMenuButton ? CGFloat(qs_menu_indicator_width(widget)) : 0
        let leading = dx + (context.environment.layoutDirection == .rightToLeft ? indicator : 0)
        func inner(_ p: ProposedViewSize) -> ProposedViewSize {
            .init(width: p.width.map { max(0, $0 - 2 * dx - indicator) }, height: p.height.map { max(0, $0 - 2 * dy) })
        }
        let button = Element { p in
            let size = child.measure(inner(p))
            return CGSize(width: size.width + 2 * dx + indicator, height: size.height + 2 * dy)
        } place: { rect, p in
            qs_place(widget, rect.minX, rect.minY, rect.width, rect.height)
            child.place(.init(origin: CGPoint(x: leading, y: dy), size: child.measure(inner(p))), inner(p))
        }
        button.baselines = { p, _ in child.baselines?(inner(p), child.measure(inner(p)))?.offset(by: dy) }
        return [button]
    }
}
public struct Toggle<Label: View>: Primitive {
    let isOn: Binding<Bool>, label: Label
    public init(isOn: Binding<Bool>, @ViewBuilder label: () -> Label) { self.isOn = isOn; self.label = label() }
    public init(_ titleKey: LocalizedStringKey, isOn: Binding<Bool>) where Label == Text {
        self.init(isOn: isOn) { Text(titleKey) }
    }
    @_disfavoredOverload public init<S: StringProtocol>(_ title: S, isOn: Binding<Bool>) where Label == Text {
        self.init(isOn: isOn) { Text(title) }
    }
    func elements(in context: Context) -> [Element] {
        if context.fieldLabelReader != nil { return label.resolve(context) }
        if let style = context.environment.toggleStyle {
            let configuration = ToggleStyleConfiguration(label: .init(content: AnyView(label), plainText: label as? Text), isOn: isOn)
            return style(configuration).resolve(context.with(\.toggleStyle, nil))
        }
        var context = context
        if context.environment.hidesControlLabels && context.environment.label.isEmpty {
            let entries = MenuEntries.commands(label, in: context)
            context.environment.label = entries.rows.map(\.title).joined(separator: " ")
        }
        let widget = context.widget(QSToggle, action: { isOn.wrappedValue = $0 == "1" })
        context.installShortcut(on: widget)
        qs_checked(widget, isOn.wrappedValue ? 1 : 0)
        if context.environment.hidesControlLabels {
            qs_text(widget, "")
            return [context.control(widget)]
        }
        if let text = (label as? Text) ?? (label as? ToggleStyleConfiguration.Label)?.plainText, text.attributed == nil {
            qs_text(widget, text.resolvedString(context.environment.locale))
            return [text.styled(context).control(widget)]
        }
        return [stacked([context.control(widget)] + label.resolve(context.descending(.position(0))), axis: .horizontal, alignment: .center, spacing: 4, direction: context.environment.layoutDirection)]
    }
}
@MainActor private func singleLineField(_ text: Binding<String>, secure: Bool, selection: EditorSelection?, callbacks: TextFieldCallbacks?, in context: Context) -> UnsafeMutableRawPointer {
    let editing = callbacks?.session(in: context)
    let widget = context.widget(secure ? QSSecureEdit : QSEdit, focusChanged: editing?.focus, submitted: editing?.commit,
                                cursorChanged: { selection?.changed($0, text: nativeEditorText($0)) },
                                action: { editing?.beginTyping(); text.wrappedValue = $0 })
    qs_text(widget, text.wrappedValue)
    selection?.apply(to: widget)
    return widget
}
public nonisolated struct TextField<Label: View>: Primitive {
    let title: FieldTitle, text: Binding<String>
    private var selection: Binding<TextSelection?>?
    var axis: Axis = .horizontal
    var prompt: Text?
    var callbacks: TextFieldCallbacks?
    var secure = false
    public init(_ titleKey: LocalizedStringKey, text: Binding<String>) where Label == Text {
        self.init(configuration: .text(Text(titleKey)), text: text, secure: false, prompt: nil, axis: .horizontal)
    }
    public init(_ titleKey: LocalizedStringKey, text: Binding<String>, axis: Axis) where Label == Text {
        self.init(configuration: .text(Text(titleKey)), text: text, secure: false, prompt: nil, axis: axis)
    }
    public init(_ titleKey: LocalizedStringKey, text: Binding<String>, prompt: Text?) where Label == Text {
        self.init(configuration: .text(Text(titleKey)), text: text, secure: false, prompt: prompt, axis: .horizontal)
    }
    public init(_ titleKey: LocalizedStringKey, text: Binding<String>, prompt: Text?, axis: Axis) where Label == Text {
        self.init(configuration: .text(Text(titleKey)), text: text, secure: false, prompt: prompt, axis: axis)
    }
    public init(_ titleKey: LocalizedStringKey, text: Binding<String>, selection: Binding<TextSelection?>, prompt: Text? = nil, axis: Axis? = nil) where Label == Text {
        self.init(configuration: .text(Text(titleKey)), text: text, secure: false, selection: selection, prompt: prompt, axis: axis ?? .horizontal)
    }
    @_disfavoredOverload public nonisolated init<S: StringProtocol>(_ title: S, text: Binding<String>) where Label == Text {
        self.init(title, text: text, prompt: nil, axis: .horizontal)
    }
    @_disfavoredOverload public nonisolated init<S: StringProtocol>(_ title: S, text: Binding<String>, axis: Axis) where Label == Text {
        self.init(title, text: text, prompt: nil, axis: axis)
    }
    @_disfavoredOverload public nonisolated init<S: StringProtocol>(_ title: S, text: Binding<String>, prompt: Text?) where Label == Text {
        self.init(title, text: text, prompt: prompt, axis: .horizontal)
    }
    @_disfavoredOverload public nonisolated init<S: StringProtocol>(_ title: S, text: Binding<String>, prompt: Text?, axis: Axis) where Label == Text {
        self.title = .text(Text(verbatim: String(title)))
        self.text = text
        self.prompt = prompt
        self.axis = axis
    }
    @_disfavoredOverload public nonisolated init<S: StringProtocol>(_ title: S, text: Binding<String>, selection: Binding<TextSelection?>, prompt: Text? = nil, axis: Axis? = nil) where Label == Text {
        self.init(title, text: text, prompt: prompt, axis: axis ?? .horizontal)
        self.selection = selection
    }
    init(configuration title: FieldTitle, text: Binding<String>, secure: Bool, selection: Binding<TextSelection?>? = nil, prompt: Text? = nil, axis: Axis = .horizontal, callbacks: TextFieldCallbacks? = nil) {
        self.callbacks = callbacks
        self.selection = selection
        self.prompt = prompt
        self.axis = axis
        self.title = title
        self.text = text
        self.secure = secure
    }
    @MainActor func elements(in context: Context) -> [Element] {
        if let style = context.environment.fieldStyle {
            let configuration = TextField<_TextFieldStyleLabel>(configuration: title, text: text, secure: secure, selection: selection, prompt: prompt, axis: axis, callbacks: callbacks)
            return style(configuration).resolve(context.with(\.fieldStyle, nil))
        }
        let label = title.resolve(in: context)
        var context = context
        let name = label.map { $0.text.resolvedString($0.locale) } ?? ""
        if context.environment.label.isEmpty { context.environment.label = name }
        let hint = prompt ?? label?.text
        let placeholder = prompt?.resolvedString(context.environment.locale) ?? name
        let hintStyle = hint?.styledEnvironment(context.environment)
        let promptColor = hint?.foregroundOverride?.resolvedPaint(in: context.environment).representativeColor.hex(context.environment.colorScheme) ?? ""
        let cursor = selection.map { EditorSelection(binding: $0, text: text, affinity: context.environment.selectionAffinity) }
        let widget = axis == .vertical ? boundEditor(QSMultilineField, text: text, selection: cursor, in: context)
                                       : singleLineField(text, secure: secure, selection: cursor, callbacks: callbacks, in: context)
        if text.wrappedValue.isEmpty, let hintStyle {
            context.with(\.font, hintStyle.font).styleControl(widget)
        } else { context.styleControl(widget) }
        qs_hint(widget, placeholder, promptColor)
        qs_field_style(widget, context.environment.fieldBorder.rawValue)
        let minimum = Int32(clamping: context.environment.minimumLines)
        let maximum = Int32(clamping: context.environment.lineLimit.map { max(1, $0) } ?? 0)
        return [Element { proposal in
            let size = qs_field_size(widget, proposal.width ?? -1, proposal.height ?? -1, minimum, maximum)
            return CGSize(width: size.width, height: size.height)
        } place: { rect, _ in qs_place(widget, rect.minX, rect.minY, rect.width, rect.height) }]
    }
}
public nonisolated struct SecureField<Label: View>: Primitive {
    let title: FieldTitle, text: Binding<String>, prompt: Text?
    var callbacks: TextFieldCallbacks?
    public init(_ titleKey: LocalizedStringKey, text: Binding<String>) where Label == Text {
        self.init(titleKey, text: text, prompt: nil)
    }
    public init(_ titleKey: LocalizedStringKey, text: Binding<String>, prompt: Text?) where Label == Text {
        title = .text(Text(titleKey))
        self.text = text
        self.prompt = prompt
    }
    @_disfavoredOverload public init<S: StringProtocol>(_ title: S, text: Binding<String>) where Label == Text {
        self.init(title, text: text, prompt: nil)
    }
    @_disfavoredOverload public init<S: StringProtocol>(_ title: S, text: Binding<String>, prompt: Text?) where Label == Text {
        self.title = .text(Text(verbatim: String(title)))
        self.text = text
        self.prompt = prompt
    }
    @MainActor func elements(in context: Context) -> [Element] {
        TextField<_TextFieldStyleLabel>(configuration: title, text: text, secure: true, prompt: prompt, callbacks: callbacks).elements(in: context)
    }
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
        guard let fraction else {
            let widget = context.widget(QSBusyIndicator)
            context.style(widget)
            let diameter: CGFloat = switch context.environment.controlSize {
            case .mini: 10
            case .small: 16
            default: 32
            }
            return [Element { _ in CGSize(width: diameter, height: diameter) } place: { rect, _ in
                qs_place(widget, rect.minX, rect.minY, rect.width, rect.height)
            }]
        }
        let widget = context.widget(QSProgress)
        qs_value(widget, fraction)
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
        qs_scroll_background(widget, context.environment.scrollBackground == .visible ? 1 : 0,
                             context.environment.colorScheme == .dark ? 1 : 0)
        var inner = context.descending(.position(0))
        inner.parent = qs_scroll_content(widget)
        let config = context.scrollConfiguration
        inner.scrollConfiguration = ScrollConfiguration()
        inner.isScrollTargetLayout = false
        inner.scrollTargets = nil
        let observesTargets = context.preferences[ObjectIdentifier(FirstScrollVisibility.self)] != nil
        if !context.registerScrollArea.isEmpty || config.active || observesTargets {
            let targets = ScrollAreaTargets(widget, axes: axes, direction: context.environment.layoutDirection)
            inner.scrollTargets = targets
            for register in context.registerScrollArea { register(targets) }
        }
        let mount: MountedScrollPosition?
        if config.active {
            let path = context.path + [.property("scroll position")]
            mount = context.host.storage[path] as? MountedScrollPosition ?? MountedScrollPosition()
            context.host.storage[path] = mount
            context.host.liveStorage.insert(path)
        } else { mount = nil }
        var visibility: ScrollVisibilitySnapshot?
        inner.publish(FirstScrollVisibility.self) { visibility }
        if axes.contains(.vertical) { inner.verticalViewport = widget }
        let origin = NamedOrigin()
        inner.spaces[ScrollSpace.nearest] = origin
        for axis in Axis.allCases where axes.contains(axis == .vertical ? .vertical : .horizontal) {
            inner.spaces[ScrollSpace.axis(axis)] = origin
        }
        var geometry: ScrollGeometry?
        inner.publish(FirstScrollGeometry.self) { geometry }
        let view = stacked(content.resolve(inner), axis: .vertical, alignment: .center, spacing: 8)
        let horizontal = axes.contains(.horizontal), vertical = axes.contains(.vertical)
        qs_scroll_input(widget, context.environment.isScrollEnabled ? 1 : 0)
        qs_scroll_bounce(widget, horizontal ? context.environment.horizontalScrollBounceBehavior.policy : -1,
                         vertical ? context.environment.verticalScrollBounceBehavior.policy : -1)
        qs_scroll_axes(widget, context.environment.isScrollEnabled && showsIndicators && horizontal ? context.environment.horizontalScrollIndicatorVisibility.qtPolicy : 0,
                       context.environment.isScrollEnabled && showsIndicators && vertical ? context.environment.verticalScrollIndicatorVisibility.qtPolicy : 0,
                       context.environment.colorScheme == .dark ? 1 : 0)
        func offer(_ p: ProposedViewSize) -> ProposedViewSize { .init(width: horizontal ? nil : p.width, height: vertical ? nil : p.height) }
        return [Element { p in
            let ideal = view.measure(offer(p))
            return CGSize(width: horizontal ? (p.width ?? ideal.width) : ideal.width,
                          height: vertical ? (p.height ?? ideal.height) : ideal.height)
        } place: { bounds, _ in
            qs_place(widget, bounds.minX, bounds.minY, bounds.width, bounds.height)
            let position = qs_origin(widget)
            origin.point = CGPoint(x: position.width, y: position.height)
            let proposal = offer(ProposedViewSize(bounds.size))
            let size = view.measure(proposal)
            let contentSize = CGSize(width: max(bounds.width, size.width), height: max(bounds.height, size.height))
            let prior = qs_scroll_viewport(widget)
            qs_scroll_size(widget, Int32(contentSize.width.rounded(.up)), Int32(contentSize.height.rounded(.up)))
            var rect = Alignment.top.rect(size, in: CGRect(origin: .zero, size: contentSize))
            var shift = CGPoint.zero
            if let mount {
                shift = mount.prepare(widget: widget, config: config, axes: axes, direction: context.environment.layoutDirection,
                                      size: size, viewport: qs_scroll_viewport(widget), prior: prior)
                if horizontal { rect.origin.x = shift.x }
                if vertical { rect.origin.y = shift.y }
            }
            view.place(rect, proposal)
            if let area = inner.scrollTargets { mount?.finish(area: area, config: config, host: context.host) }
            let viewport = qs_scroll_viewport(widget)
            if observesTargets {
                visibility = inner.scrollTargets?.snapshot(in: CGRect(x: viewport.x, y: viewport.y, width: viewport.width, height: viewport.height))
            }
            geometry = ScrollGeometry(contentOffset: CGPoint(x: viewport.x - shift.x, y: viewport.y - shift.y), contentSize: size,
                                      contentInsets: EdgeInsets(), containerSize: CGSize(width: viewport.width, height: viewport.height))
        }]
    }
}
