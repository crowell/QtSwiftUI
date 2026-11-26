public struct EdgeInsets: Equatable, Sendable {
    public var top, leading, bottom, trailing: CGFloat
    public init(top: CGFloat, leading: CGFloat, bottom: CGFloat, trailing: CGFloat) {
        self.top = top; self.leading = leading; self.bottom = bottom; self.trailing = trailing
    }
    public init() { self.init(top: 0, leading: 0, bottom: 0, trailing: 0) }
}
public enum Edge: Int8, CaseIterable, Sendable {
    case top, leading, bottom, trailing
    public struct Set: OptionSet, Sendable {
        public let rawValue: Int8
        public init(rawValue: Int8) { self.rawValue = rawValue }
        public static let top = Self(rawValue: 1), leading = Self(rawValue: 2), bottom = Self(rawValue: 4), trailing = Self(rawValue: 8)
        public static let horizontal: Self = [.leading, .trailing], vertical: Self = [.top, .bottom], all: Self = [.horizontal, .vertical]
    }
}
struct Transform<Content: View>: Primitive, SubviewSource {
    let content: Content
    var readingContext: (Context) -> Context = { $0 }
    let transform: (any View, Context) -> [Element]
    func subviews(in context: Context) -> [Subview] {
        content.collectSubviews(in: readingContext(context)).map { $0.applying(transform) }
    }
    func elements(in context: Context) -> [Element] { transform(content, context) }
}
@MainActor @preconcurrency public protocol ViewModifier {
    associatedtype Body: View
    typealias Content = _ViewModifier_Content<Self>
    @MainActor @ViewBuilder func body(content: Content) -> Body
}
@MainActor protocol PrimitiveModifier: ViewModifier where Body == Never {
    func applying(to content: AnyView) -> any View
}
public struct _ViewModifier_Content<Modifier: ViewModifier>: View {
    let view: AnyView
    public var body: some View { view }
}
public struct ModifiedContent<Content, Modifier> {
    public let content: Content
    public let modifier: Modifier
    public init(content: Content, modifier: Modifier) { self.content = content; self.modifier = modifier }
}
extension ModifiedContent: Primitive, View, SubviewSource where Content: View, Modifier: ViewModifier {
    func subviews(in context: Context) -> [Subview] {
        applied(in: context).collectSubviews(in: context)
    }
    func elements(in context: Context) -> [Element] {
        applied(in: context).resolve(context)
    }
    @MainActor private func applied(in context: Context) -> any View {
        let modifier = context.preparing(modifier)
        if let primitive = modifier as? any PrimitiveModifier { return primitive.applying(to: AnyView(content)) }
        return modifier.body(content: .init(view: AnyView(content)))
    }
}
extension View {
    public func modifier<M: ViewModifier>(_ modifier: M) -> ModifiedContent<Self, M> { .init(content: self, modifier: modifier) }
    public func environment<V>(_ keyPath: WritableKeyPath<EnvironmentValues, V>, _ value: V) -> some View {
        Transform(content: self, readingContext: { $0.with(keyPath, value) }) { $0.resolve($1.with(keyPath, value)) }
    }
    public func id<ID: Hashable>(_ id: ID) -> some View { Transform(content: self) { $0.resolve($1.descending(.id(AnyHashable(id)))) } }
    public func font(_ font: Font?) -> some View { environment(\.font, font) }
    public func fontWeight(_ weight: Font.Weight?) -> some View {
        Transform(content: self) { view, ctx in view.resolve(ctx.with(\.font, (ctx.environment.font ?? .body).weight(weight ?? .regular))) }
    }
    public func bold(_ active: Bool = true) -> some View { fontWeight(active ? .bold : nil) }
    public func foregroundColor(_ color: Color?) -> some View { environment(\.foreground, color ?? .primary) }
    public func foregroundStyle<S: ShapeStyle>(_ style: S) -> some View {
        Transform(content: self) { view, ctx in view.resolve(ctx.with(\.foreground, style.color(in: ctx.environment))) }
    }
    public func multilineTextAlignment(_ alignment: TextAlignment) -> some View { environment(\.multilineTextAlignment, alignment) }
    public func lineLimit(_ number: Int?) -> some View { environment(\.lineLimit, number) }
    public func allowsHitTesting(_ enabled: Bool) -> some View {
        Transform(content: self) { view, ctx in
            view.resolve(ctx.with(\.allowsHits, ctx.environment.allowsHits && enabled))
        }
    }
    public func disabled(_ disabled: Bool) -> some View {
        Transform(content: self) { view, ctx in view.resolve(ctx.with(\.isEnabled, ctx.environment.isEnabled && !disabled)) }
    }
    public func accessibilityLabel(_ label: String) -> some View { environment(\.label, label) }
    public func accessibilityIdentifier(_ identifier: String) -> some View { environment(\.identifier, identifier) }
    public func layoutValue<K: LayoutValueKey>(key: K.Type, value: K.Value) -> some View {
        Transform(content: self) { view, ctx in
            let items = view.resolve(ctx)
            for item in items { item.values[ObjectIdentifier(key)] = value }
            return items
        }
    }
    public func layoutPriority(_ value: Double) -> some View {
        Transform(content: self) { view, ctx in
            let items = view.resolve(ctx)
            for item in items { item.priority = value }
            return items
        }
    }
    public func padding(_ length: CGFloat) -> some View { padding(.all, length) }
    public func padding(_ edges: Edge.Set = .all, _ length: CGFloat? = nil) -> some View {
        let n = length ?? 16
        return padding(EdgeInsets(top: edges.contains(.top) ? n : 0, leading: edges.contains(.leading) ? n : 0,
                                  bottom: edges.contains(.bottom) ? n : 0, trailing: edges.contains(.trailing) ? n : 0))
    }
    public func padding(_ insets: EdgeInsets) -> some View {
        Transform(content: self) { view, ctx in
            let left = ctx.environment.layoutDirection == .rightToLeft ? insets.trailing : insets.leading
            let w = insets.leading + insets.trailing, h = insets.top + insets.bottom
            func inner(_ p: ProposedViewSize) -> ProposedViewSize {
                .init(width: p.width.map { max(0, $0 - w) }, height: p.height.map { max(0, $0 - h) })
            }
            return view.resolve(ctx).map { child in
                child.wrapping { p in
                    let size = child.measure(inner(p))
                    return CGSize(width: size.width + w, height: size.height + h)
                } place: { rect, p in
                    child.place(CGRect(origin: CGPoint(x: rect.minX + left, y: rect.minY + insets.top),
                                       size: child.measure(inner(p))), inner(p))
                }
            }
        }
    }
    public func frame(width: CGFloat? = nil, height: CGFloat? = nil, alignment: Alignment = .center) -> some View {
        frame(minWidth: width, idealWidth: width, maxWidth: width, minHeight: height, idealHeight: height, maxHeight: height, alignment: alignment)
    }
    public func frame(minWidth: CGFloat? = nil, idealWidth: CGFloat? = nil, maxWidth: CGFloat? = nil,
                      minHeight: CGFloat? = nil, idealHeight: CGFloat? = nil, maxHeight: CGFloat? = nil, alignment: Alignment = .center) -> some View {
        Transform(content: self) { view, ctx in
            func clamp(_ n: CGFloat, _ low: CGFloat?, _ high: CGFloat?) -> CGFloat { min(max(n, low ?? 0), high ?? .infinity) }
            func proposed(_ p: ProposedViewSize) -> ProposedViewSize {
                ProposedViewSize(width: (p.width ?? idealWidth).map { clamp($0, minWidth, maxWidth) },
                                 height: (p.height ?? idealHeight).map { clamp($0, minHeight, maxHeight) })
            }
            func dimension(_ content: CGFloat, _ offer: CGFloat?, _ low: CGFloat?, _ high: CGFloat?) -> CGFloat {
                var result = content
                if let offer, low != nil { result = min(result, offer) }
                if let offer, high != nil { result = max(result, offer) }
                return clamp(result, low, high)
            }
            return view.resolve(ctx).map { child in
                child.wrapping { p in
                    let offer = proposed(p), size = child.measure(offer)
                    return CGSize(width: dimension(size.width, offer.width, minWidth, maxWidth),
                                  height: dimension(size.height, offer.height, minHeight, maxHeight))
                } place: { bounds, p in
                    let offer = proposed(p)
                    child.place(alignment.rect(child.measure(offer), in: bounds, direction: ctx.environment.layoutDirection), offer)
                }
            }
        }
    }
    public func fixedSize(horizontal: Bool, vertical: Bool) -> some View {
        Transform(content: self) { view, ctx in
            func offer(_ p: ProposedViewSize) -> ProposedViewSize { .init(width: horizontal ? nil : p.width, height: vertical ? nil : p.height) }
            return view.resolve(ctx).map { child in child.wrapping { child.measure(offer($0)) } place: { child.place($0, offer($1)) } }
        }
    }
    public func fixedSize() -> some View { fixedSize(horizontal: true, vertical: true) }
    public func background<B: View>(_ background: B, alignment: Alignment = .center) -> some View {
        decorated(background, alignment: alignment, above: false)
    }
    public func background<B: View>(alignment: Alignment = .center, @ViewBuilder content: () -> B) -> some View {
        decorated(content(), alignment: alignment, above: false)
    }
    public func overlay<V: View>(_ overlay: V, alignment: Alignment = .center) -> some View {
        decorated(overlay, alignment: alignment, above: true)
    }
    public func overlay<V: View>(alignment: Alignment = .center, @ViewBuilder content: () -> V) -> some View {
        decorated(content(), alignment: alignment, above: true)
    }
    private func decorated<V: View>(_ decoration: V, alignment: Alignment, above: Bool) -> some View {
        Transform(content: self) { view, ctx in
            view.resolve(ctx.descending(.position(0))).enumerated().map { index, child in
                let decorations = decoration.resolve(ctx.descending(.position(1)).descending(.position(index)))
                return child.wrapping(size: child.measure) { bounds, p in
                    let proposal = ProposedViewSize(bounds.size)
                    if above { child.place(bounds, p) }
                    for d in decorations { d.place(alignment.rect(d.measure(proposal), in: bounds, direction: ctx.environment.layoutDirection), proposal) }
                    if !above { child.place(bounds, p) }
                }
            }
        }
    }
}
