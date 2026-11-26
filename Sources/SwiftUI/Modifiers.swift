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
nonisolated struct Transform<Content: View>: Primitive, SubviewSource {
    let content: Content
    var readingContext: @MainActor (Context) -> Context = { $0 }
    let transform: @MainActor (any View, Context) -> [Element]
    @MainActor func subviews(in context: Context) -> [Subview] {
        content.collectSubviews(in: readingContext(context)).map { $0.applying(transform) }
    }
    @MainActor func elements(in context: Context) -> [Element] { transform(content, context) }
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
        Transform(content: self) { view, ctx in view.resolve(ctx.with(\.foregroundPaint, style.paint(in: ctx.environment))) }
    }
    public func multilineTextAlignment(_ alignment: TextAlignment) -> some View { environment(\.multilineTextAlignment, alignment) }
    nonisolated public func lineLimit(_ number: Int?) -> some View { limits(minimum: 1, maximum: number) }
    nonisolated public func lineLimit(_ limit: ClosedRange<Int>) -> some View { limits(minimum: limit.lowerBound, maximum: limit.upperBound) }
    nonisolated public func lineLimit(_ limit: PartialRangeFrom<Int>) -> some View { limits(minimum: limit.lowerBound, maximum: nil) }
    nonisolated public func lineLimit(_ limit: PartialRangeThrough<Int>) -> some View { limits(minimum: 1, maximum: limit.upperBound) }
    nonisolated public func lineLimit(_ limit: Int, reservesSpace: Bool) -> some View { limits(minimum: reservesSpace ? limit : 1, maximum: limit) }

    private nonisolated func limits(minimum: Int, maximum: Int?) -> some View {
        let apply: @MainActor (Context) -> Context = { context in
            var copy = context
            copy.environment.lineLimit = maximum
            copy.environment.minimumLines = max(1, minimum)
            return copy
        }
        return Transform(content: self, readingContext: apply) { $0.resolve(apply($1)) }
    }
    nonisolated public func autocorrectionDisabled(_ disable: Bool = true) -> some View {
        Transform(content: self) { $0.resolve($1.with(\.autocorrectionDisabled, disable)) }
    }
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
    nonisolated public func padding(_ length: CGFloat) -> some View { padding(.all, length) }
    nonisolated public func padding(_ edges: Edge.Set = .all, _ length: CGFloat? = nil) -> some View {
        let n = length ?? 16
        return padding(EdgeInsets(top: edges.contains(.top) ? n : 0, leading: edges.contains(.leading) ? n : 0,
                                  bottom: edges.contains(.bottom) ? n : 0, trailing: edges.contains(.trailing) ? n : 0))
    }
    nonisolated public func padding(_ insets: EdgeInsets) -> some View {
        Transform(content: self) { view, ctx in
            let left = ctx.environment.layoutDirection == .rightToLeft ? insets.trailing : insets.leading
            let w = insets.leading + insets.trailing, h = insets.top + insets.bottom
            func inner(_ p: ProposedViewSize) -> ProposedViewSize {
                .init(width: p.width.map { max(0, $0 - w) }, height: p.height.map { max(0, $0 - h) })
            }
            return view.resolve(ctx).map { child in
                let padded = child.wrapping { p in
                    let size = child.measure(inner(p))
                    return CGSize(width: size.width + w, height: size.height + h)
                } baselines: { p, _ in
                    child.baselines?(inner(p), child.measure(inner(p)))?.offset(by: insets.top)
                } place: { rect, p in
                    child.place(CGRect(origin: CGPoint(x: rect.minX + left, y: rect.minY + insets.top),
                                       size: child.measure(inner(p))), inner(p))
                }
                padded.translateGuides(from: child) { p, _ in
                    (CGRect(origin: CGPoint(x: insets.leading, y: insets.top), size: child.measure(inner(p))), inner(p))
                }
                return padded
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
                @MainActor func measured(_ proposal: ProposedViewSize) -> (offer: ProposedViewSize, size: CGSize) {
                    var offer = proposed(proposal)
                    let ideal = child.measure(offer)
                    if offer.width == nil {
                        let width = clamp(ideal.width, minWidth, maxWidth)
                        if width != ideal.width { offer.width = width }
                    }
                    if offer.height == nil {
                        let height = clamp(ideal.height, minHeight, maxHeight)
                        if height != ideal.height { offer.height = height }
                    }
                    return (offer, child.measure(offer))
                }
                let framed = child.wrapping { p in
                    let (offer, size) = measured(p)
                    return CGSize(width: dimension(size.width, offer.width, minWidth, maxWidth),
                                  height: dimension(size.height, offer.height, minHeight, maxHeight))
                } baselines: { p, outer in
                    let (offer, size) = measured(p)
                    let y = alignment.rect(for: child, size: size, proposal: offer, in: CGRect(origin: .zero, size: outer)).minY
                    return child.baselines?(offer, size)?.offset(by: y)
                } place: { bounds, p in
                    let (offer, size) = measured(p)
                    child.place(alignment.rect(for: child, size: size, proposal: offer, in: bounds, direction: ctx.environment.layoutDirection), offer)
                }
                framed.translateGuides(from: child) { p, outer in
                    let (offer, size) = measured(p)
                    return (alignment.rect(for: child, size: size, proposal: offer, in: CGRect(origin: .zero, size: outer)), offer)
                }
                return framed
            }
        }
    }
    public func fixedSize(horizontal: Bool, vertical: Bool) -> some View {
        Transform(content: self) { view, ctx in
            func offer(_ p: ProposedViewSize) -> ProposedViewSize { .init(width: horizontal ? nil : p.width, height: vertical ? nil : p.height) }
            return view.resolve(ctx).map { child in
                let fixed = child.wrapping { child.measure(offer($0)) } baselines: { p, size in child.baselines?(offer(p), size) } place: { child.place($0, offer($1)) }
                fixed.translateGuides(from: child) { p, size in (CGRect(origin: .zero, size: size), offer(p)) }
                return fixed
            }
        }
    }
    public func fixedSize() -> some View { fixedSize(horizontal: true, vertical: true) }
    nonisolated public func background<B: View>(_ background: B, alignment: Alignment = .center) -> some View {
        decorated(background, alignment: alignment, above: false)
    }
    nonisolated public func background<B: View>(alignment: Alignment = .center, @ViewBuilder content: () -> B) -> some View {
        decorated(content(), alignment: alignment, above: false)
    }
    nonisolated public func overlay<V: View>(_ overlay: V, alignment: Alignment = .center) -> some View {
        decorated(overlay, alignment: alignment, above: true)
    }
    nonisolated public func overlay<V: View>(alignment: Alignment = .center, @ViewBuilder content: () -> V) -> some View {
        decorated(content(), alignment: alignment, above: true)
    }
    nonisolated private func decorated<V: View>(_ decoration: V, alignment: Alignment, above: Bool) -> some View {
        DecoratedView(content: self, decoration: decoration, alignment: alignment, above: above)
    }
}

private nonisolated struct DecoratedView<Content: View, Decoration: View>: View {
    let content: Content
    let decoration: Decoration
    let alignment: Alignment
    let above: Bool

    @MainActor var body: some View {
        Transform(content: content) { view, ctx in
            view.resolve(ctx.descending(.position(0))).enumerated().map { index, child in
                let decorations = decoration.resolve(ctx.descending(.position(1)).descending(.position(index)))
                return child.wrapping(size: child.measure) { bounds, p in
                    let proposal = ProposedViewSize(bounds.size)
                    if above { child.place(bounds, p) }
                    for decoration in decorations {
                        let size = decoration.measure(proposal)
                        let rect = alignment.rect(for: decoration, size: size, proposal: proposal, in: bounds, parent: child,
                                                  parentProposal: p, direction: ctx.environment.layoutDirection)
                        decoration.place(rect, proposal)
                    }
                    if !above { child.place(bounds, p) }
                }
            }
        }
    }
}
