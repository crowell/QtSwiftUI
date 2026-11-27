import QtBridge

@MainActor struct ScrollConfiguration {
    var defaultAnchor: UnitPoint?
    var roleAnchors: [ScrollAnchorRole: UnitPoint?] = [:]
    var position: Binding<ScrollPosition>?
    var id: IDBinding?
    var anchor: UnitPoint?

    struct IDBinding {
        let read: () -> AnyHashable?
        let write: (AnyHashable?) -> Void
        let accepts: (AnyHashable) -> Bool
    }
    func anchor(for role: ScrollAnchorRole) -> UnitPoint? {
        if let specific = roleAnchors[role] { return specific }
        return defaultAnchor
    }
    var active: Bool { defaultAnchor != nil || !roleAnchors.isEmpty || position != nil || id != nil }
}

private nonisolated struct IDPositionView<Content: View, ID: Hashable>: View {
    let content: Content
    let position: Binding<ID?>
    let anchor: UnitPoint?
    @MainActor var body: some View {
        Transform(content: content) { view, context in
            var inner = context
            inner.scrollConfiguration.id = .init(read: { position.wrappedValue.map(AnyHashable.init) },
                write: { position.wrappedValue = $0?.base as? ID }, accepts: { $0.base is ID })
            inner.scrollConfiguration.anchor = anchor
            return view.resolve(inner)
        }
    }
}

private nonisolated struct PositionView<Content: View>: View {
    let content: Content
    let position: Binding<ScrollPosition>
    let anchor: UnitPoint?
    @MainActor var body: some View {
        Transform(content: content) { view, context in
            var inner = context
            inner.scrollConfiguration.position = position
            inner.scrollConfiguration.anchor = anchor
            return view.resolve(inner)
        }
    }
}

extension View {
    nonisolated public func defaultScrollAnchor(_ anchor: UnitPoint?) -> some View {
        Transform(content: self) { view, context in
            var inner = context
            inner.scrollConfiguration.defaultAnchor = anchor
            return view.resolve(inner)
        }
    }

    nonisolated public func defaultScrollAnchor(_ anchor: UnitPoint?, for role: ScrollAnchorRole) -> some View {
        Transform(content: self) { view, context in
            var inner = context
            inner.scrollConfiguration.roleAnchors.updateValue(anchor, forKey: role)
            return view.resolve(inner)
        }
    }

    nonisolated public func scrollPosition(_ position: Binding<ScrollPosition>, anchor: UnitPoint? = nil) -> some View {
        PositionView(content: self, position: position, anchor: anchor)
    }

    nonisolated public func scrollPosition(id: Binding<(some Hashable)?>, anchor: UnitPoint? = nil) -> some View {
        IDPositionView(content: self, position: id, anchor: anchor)
    }
}

@MainActor final class MountedScrollPosition {
    private var range: CGSize?
    private var offset = CGPoint.zero
    private var position: ScrollPosition?
    private var bindingID: AnyHashable?
    private var deferredID: AnyHashable?
    private var idAnchor: UnitPoint?
    private var commandAnimation: Animation?
    private var userRevision: UInt64 = 0
    private var holdsPosition = false
    private var didScrollByUser = false

    private func physicalX(_ anchor: UnitPoint, direction: LayoutDirection) -> CGFloat {
        direction == .leftToRight ? anchor.x : 1 - anchor.x
    }

    func prepare(area: ScrollAreaTargets, animation: Animation?, config: ScrollConfiguration, axes: Axis.Set, direction: LayoutDirection,
                 size: CGSize, viewport: QSRect, prior: QSRect) -> CGPoint {
        let widget = area.widget
        let maximum = CGSize(width: axes.contains(.horizontal) ? max(0, size.width - viewport.width) : 0,
                             height: axes.contains(.vertical) ? max(0, size.height - viewport.height) : 0)
        let shortAnchor = config.anchor(for: .alignment)
        let shift = CGPoint(x: axes.contains(.horizontal) ? max(0, viewport.width - size.width) * (shortAnchor.map { physicalX($0, direction: direction) } ?? 0.5) : 0,
                            y: axes.contains(.vertical) ? max(0, viewport.height - size.height) * (shortAnchor?.y ?? 0) : 0)
        let selected = config.position?.wrappedValue, id = config.id?.read()
        let first = range == nil, changed = position != selected || bindingID != id
        let revision = qs_scroll_user_revision(widget)
        let userMoved = !first && revision != userRevision
        didScrollByUser = userMoved && !changed
        userRevision = revision
        var next = CGPoint(x: viewport.x, y: viewport.y)
        let oldOffset = CGPoint(x: prior.x, y: prior.y)
        let resized = range != maximum
        if first, let anchor = config.anchor(for: .initialOffset) {
            next = CGPoint(x: maximum.width * physicalX(anchor, direction: direction), y: maximum.height * anchor.y)
        } else if let range, resized, let initial = config.anchor(for: .initialOffset) {
            // Keep an anchored position through changes to the document or the viewport.
            let anchor = config.anchor(for: .sizeChanges) ?? initial
            let x = physicalX(anchor, direction: direction)
            if abs(oldOffset.x - range.width * x) < 1 { next.x = maximum.width * x }
            if abs(oldOffset.y - range.height * anchor.y) < 1 { next.y = maximum.height * anchor.y }
        }
        if changed || first { holdsPosition = true; commandAnimation = first ? nil : animation }
        else if userMoved || (!resized && oldOffset != offset) { holdsPosition = false }
        if changed || first || (resized && holdsPosition) {
            switch selected?.destination {
            case .edge(let edge):
                switch edge {
                case .top: next.y = 0
                case .bottom: next.y = maximum.height
                case .leading: next.x = direction == .leftToRight ? 0 : maximum.width
                case .trailing: next.x = direction == .leftToRight ? maximum.width : 0
                }
            case .point(let point) where changed || first: next = point
            case .x(let x) where changed || first: next.x = x
            case .y(let y) where changed || first: next.y = y
            case .id(let id, let anchor):
                deferredID = AnyHashable(id)
                idAnchor = anchor ?? config.anchor
            default: break
            }
            if let id { deferredID = id; idAnchor = config.anchor }
        }
        if didScrollByUser { deferredID = nil }
        if changed, id == nil, selected?.viewID == nil { deferredID = nil }
        position = selected
        bindingID = id
        range = maximum
        let target = CGPoint(x: axes.contains(.horizontal) ? next.x : viewport.x, y: axes.contains(.vertical) ? next.y : viewport.y)
        let commanded: Bool
        switch selected?.destination {
        case .point, .edge, .x, .y: commanded = changed
        default: commanded = false
        }
        if commanded || target != CGPoint(x: viewport.x, y: viewport.y) {
            area.motion.move(widget: widget, to: target, animation: changed ? commandAnimation : nil)
        }
        return shift
    }

    func finish(area: ScrollAreaTargets, config: ScrollConfiguration, host: Host) {
        var resolved = false
        if let id = deferredID, let target = area.target(for: id) {
            area.scroll(to: target.rect, anchor: idAnchor, animation: commandAnimation)
            if !target.estimated { deferredID = nil }
            resolved = true
        }
        let view = qs_scroll_viewport(area.widget)
        offset = CGPoint(x: view.x, y: view.y)
        if didScrollByUser, !resolved, deferredID == nil {
            let rect = CGRect(x: view.x, y: view.y, width: view.width, height: view.height)
            let anchor = config.anchor ?? .topLeading
            let x = physicalX(anchor, direction: area.direction)
            let target = CGPoint(x: rect.minX + rect.width * x, y: rect.minY + rect.height * anchor.y)
            let entries = area.snapshot(in: rect).entries.filter {
                (config.id?.accepts($0.id) == true || position?.accepts($0.id) == true) && !$0.rect.intersection(rect).isEmpty
            }
            let nearest = entries.min { a, b in
                func distance(_ r: CGRect) -> CGFloat {
                    let dx = area.axes.contains(.horizontal) ? r.minX + r.width * x - target.x : 0
                    let dy = area.axes.contains(.vertical) ? r.minY + r.height * anchor.y - target.y : 0
                    return dx * dx + dy * dy
                }
                return distance(a.rect) < distance(b.rect)
            }?.id
            if let binding = config.position, var value = position {
                value.userScrolled(to: nearest)
                if value != position {
                    let expected = position
                    host.afterLayout { if binding.wrappedValue == expected { binding.wrappedValue = value } }
                }
            }
            if let binding = config.id, nearest != bindingID {
                bindingID = nearest
                host.afterLayout { if binding.read() != nearest { binding.write(nearest) } }
            }
        }
    }
}
