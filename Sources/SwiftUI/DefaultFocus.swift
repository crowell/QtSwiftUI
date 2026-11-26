import QtBridge

public struct DefaultFocusEvaluationPriority: Sendable {
    let includesKeyboardNavigation: Bool
    public static let automatic = Self(includesKeyboardNavigation: false)
    public static let userInitiated = Self(includesKeyboardNavigation: true)
}

struct FocusTarget: Hashable {
    let state: ObjectIdentifier
    let value: AnyHashable
}

struct DefaultFocusRegion {
    let path: [Part]
    let preferred: FocusTarget
    let priority: DefaultFocusEvaluationPriority
}

@MainActor final class WindowDefaultFocus {
    private var members: [Int32: [DefaultFocusRegion]] = [:]
    private var targets: [[Part]: [UnsafeMutableRawPointer]] = [:]
    private var order: [[Part]] = []
    private var previousRegions: Set<[Part]>?
    private var current: Int32?
    private var enteredRegions: [[Part]] = []
    private var directing = false

    func begin() {
        members.removeAll(keepingCapacity: true)
        targets.removeAll(keepingCapacity: true)
        order.removeAll(keepingCapacity: true)
    }

    func include(id: Int32, widget: UnsafeMutableRawPointer, regions: [DefaultFocusRegion], focus: FocusLink?) {
        guard !regions.isEmpty else { return }
        members[id] = regions
        guard let target = focus?.target else { return }
        for region in regions.reversed() where target == region.preferred {
            if targets[region.path] == nil { order.append(region.path) }
            targets[region.path, default: []].append(widget)
        }
    }

    func entered(id: Int32, reason: String) -> Bool {
        let previous = current
        current = id
        enteredRegions.removeAll(keepingCapacity: true)
        guard !directing, reason != "mouse", let regions = members[id] else { return false }
        let old = previous.flatMap { members[$0] } ?? []
        for region in regions.reversed() where reason != "tab" || region.priority.includesKeyboardNavigation {
            if !old.contains(where: { $0.path == region.path }) { enteredRegions.append(region.path) }
        }
        return !enteredRegions.isEmpty
    }

    func finish(window: OpaquePointer) {
        let new = Set(order).subtracting(previousRegions ?? [])
        let initializing = previousRegions == nil
        previousRegions = Set(order)
        directing = true
        defer { directing = false }
        let requested = enteredRegions
        enteredRegions.removeAll(keepingCapacity: true)
        for region in requested {
            if move(in: region) { return }
        }
        if !new.isEmpty && (initializing || qs_window_has_focus(window) == 0) {
            for region in order where new.contains(region) {
                if move(in: region) { return }
            }
        }
    }

    private func move(in region: [Part]) -> Bool {
        for widget in targets[region] ?? [] {
            if qs_try_focus(widget) != 0 { return true }
        }
        return false
    }
}

private nonisolated struct DefaultFocusView<Content: View>: View {
    let content: Content
    let preferred: FocusTarget
    let priority: DefaultFocusEvaluationPriority

    @MainActor var body: some View {
        let apply: @MainActor (Context) -> Context = { ctx in
            var inner = ctx
            inner.defaultFocusRegions.append(DefaultFocusRegion(path: ctx.path, preferred: preferred, priority: priority))
            return inner
        }
        return Transform(content: content, readingContext: apply) { $0.resolve(apply($1)) }
    }
}

extension View {
    nonisolated public func defaultFocus<V>(_ binding: FocusState<V>.Binding, _ value: V,
                                            priority: DefaultFocusEvaluationPriority = .automatic) -> some View where V: Hashable {
        DefaultFocusView(content: self, preferred: binding.target(for: value), priority: priority)
    }
}
