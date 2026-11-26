import QtBridge

public struct ResetFocusAction {
    let reset: (Namespace.ID) -> Void
    public func callAsFunction(in namespace: Namespace.ID) { reset(namespace) }
}

extension EnvironmentValues {
    public var resetFocus: ResetFocusAction { focusReset }
}

@MainActor final class WindowFocusScopes {
    struct Candidate {
        let widget: UnsafeMutableRawPointer
        let scopes: Set<Namespace.ID>
        let preferences: Set<Namespace.ID>
    }

    private var candidates: [Candidate] = []
    private var previousScopes: Set<Namespace.ID>?

    func begin() { candidates.removeAll(keepingCapacity: true) }

    func include(_ widget: UnsafeMutableRawPointer, environment: EnvironmentValues) {
        guard !environment.focusScopes.isEmpty else { return }
        candidates.append(Candidate(widget: widget, scopes: environment.focusScopes,
                                    preferences: environment.preferredFocus.intersection(environment.focusScopes)))
    }

    func finish(window: OpaquePointer) {
        let scopes = candidates.reduce(into: Set<Namespace.ID>()) { $0.formUnion($1.scopes) }
        let appearing = scopes.subtracting(previousScopes ?? [])
        let initial = previousScopes == nil
        previousScopes = scopes
        guard !appearing.isEmpty, initial || qs_window_has_focus(window) == 0 else { return }
        for item in candidates where !item.preferences.isDisjoint(with: appearing) {
            if qs_try_focus(item.widget) != 0 { return }
        }
    }

    func reset(in scope: Namespace.ID) {
        let members = candidates.filter { $0.scopes.contains(scope) }
        for item in members where item.preferences.contains(scope) {
            if qs_try_focus(item.widget) != 0 { return }
        }
        for item in members where !item.preferences.contains(scope) {
            if qs_try_focus(item.widget) != 0 { return }
        }
    }
}

extension View {
    nonisolated public func focusScope(_ namespace: Namespace.ID) -> some View {
        let apply: @MainActor (Context) -> Context = { ctx in
            ctx.with(\.focusScopes, ctx.environment.focusScopes.union([namespace]))
        }
        return Transform(content: self, readingContext: apply) { $0.resolve(apply($1)) }
    }

    nonisolated public func prefersDefaultFocus(_ prefersDefaultFocus: Bool = true, in namespace: Namespace.ID) -> some View {
        let apply: @MainActor (Context) -> Context = { ctx in
            var preferences = ctx.environment.preferredFocus
            if prefersDefaultFocus { preferences.insert(namespace) } else { preferences.remove(namespace) }
            return ctx.with(\.preferredFocus, preferences)
        }
        return Transform(content: self, readingContext: apply) { $0.resolve(apply($1)) }
    }
}
