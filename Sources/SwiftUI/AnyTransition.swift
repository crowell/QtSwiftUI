import QtBridge

public struct AnyTransition {
    struct Effect {
        var fades: Bool
        var animation: Animation?
    }
    var insertion: Effect
    var removal: Effect

    private init(fades: Bool) {
        insertion = Effect(fades: fades)
        removal = insertion
    }

    public static var opacity: Self { Self(fades: true) }
    public static var identity: Self { Self(fades: false) }

    public static func asymmetric(insertion: AnyTransition, removal: AnyTransition) -> AnyTransition {
        var result = insertion
        result.removal = removal.removal
        return result
    }

    public func animation(_ animation: Animation?) -> AnyTransition {
        var result = self
        result.insertion.animation = animation
        result.removal.animation = animation
        return result
    }
}

extension View {
    public nonisolated func transition(_ t: AnyTransition) -> some View {
        TransitionView(content: self, transition: t)
    }
}

private nonisolated struct TransitionView<Content: View>: Primitive {
    let content: Content
    let transition: AnyTransition

    @MainActor func elements(in context: Context) -> [Element] {
        let layer = context.widget(QSGroup)
        return context.children(of: content, inside: layer).map { item in
            item.wrapping(size: item.measure) { rect, proposal in
                context.host.transitions.place(at: context.path, layer: layer, transition: transition, context: context)
                item.place(rect, proposal)
            }
        }
    }
}

@MainActor final class ViewTransitions {
    private final class Entry {
        var source: UnsafeMutableRawPointer?
        var snapshot: UnsafeMutableRawPointer?
        var removal: AnyTransition.Effect
        let opacity: AnimatedValue<Double>

        init(removal: AnyTransition.Effect, opacity: Double) {
            self.removal = removal
            self.opacity = AnimatedValue(opacity)
        }
    }

    private var entries: [[Part]: Entry] = [:]
    private var placed = Set<[Part]>()
    private var scopes: [[Part]: Transaction] = [:]

    func begin() {
        placed.removeAll(keepingCapacity: true)
        scopes.removeAll(keepingCapacity: true)
    }

    func record(_ transaction: Transaction, at path: [Part]) {
        if !entries.isEmpty { scopes[path] = transaction }
    }

    func place(at path: [Part], layer: UnsafeMutableRawPointer, transition: AnyTransition, context: Context) {
        placed.insert(path)
        let animation = transition.insertion.animation ?? context.animation
        let fades = transition.insertion.fades && animation != nil
        let entry = entries[path] ?? Entry(removal: transition.removal, opacity: fades ? 0 : 1)
        entries[path] = entry
        if let snapshot = entry.snapshot {
            qs_destroy(snapshot)
            entry.snapshot = nil
        }
        entry.source = layer
        entry.removal = transition.removal
        entry.opacity.update(to: 1, at: context.host.frameTime, animation: fades ? animation : nil)
        paint(entry.opacity, layer: layer, host: context.host)
    }

    private func paint(_ opacity: AnimatedValue<Double>, layer: UnsafeMutableRawPointer, host: Host) {
        qs_group_opacity(layer, opacity.sample(at: host.frameTime))
        if opacity.isAnimating { qs_animation_frame(host.window) }
    }

    func finish(host: Host, transaction: Transaction) {
        let removed = Set(entries.keys.filter { !placed.contains($0) && entries[$0]?.source != nil })
        for path in Array(entries.keys) where !placed.contains(path) {
            guard let entry = entries[path] else { continue }
            if let source = entry.source {
                var prefix = path
                var scope: Transaction?
                var ancestorDisappeared = false
                while !prefix.isEmpty {
                    prefix.removeLast()
                    if removed.contains(prefix) { ancestorDisappeared = true; break }
                    if scope == nil { scope = scopes[prefix] }
                }
                let animation = entry.removal.animation ?? (scope ?? transaction).animation
                guard !ancestorDisappeared, entry.removal.fades, let animation,
                      let snapshot = qs_transition_snapshot(host.window, source) else {
                    entries[path] = nil
                    continue
                }
                entry.snapshot = snapshot
                entry.source = nil
                entry.opacity.update(to: 0, at: host.frameTime, animation: animation)
            }
            if let snapshot = entry.snapshot {
                qs_transition_front(snapshot)
                paint(entry.opacity, layer: snapshot, host: host)
                if !entry.opacity.isAnimating {
                    qs_destroy(snapshot)
                    entries[path] = nil
                }
            }
        }
    }
}
