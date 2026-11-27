import QtBridge

public protocol PreferenceKey {
    associatedtype Value
    static var defaultValue: Value { get }
    static func reduce(value: inout Value, nextValue: () -> Value)
}

extension PreferenceKey where Value: ExpressibleByNilLiteral {
    public static var defaultValue: Value { nil }
}

@MainActor protocol PreferenceScope: AnyObject {
    func branch() -> any PreferenceScope
}

// Reserve sibling slots during traversal. A GeometryReader can fill its slot
// later, during placement, without changing the order seen by the reducer.
@MainActor private final class PreferenceValues<K: PreferenceKey>: PreferenceScope {
    typealias Producer = () -> K.Value
    var inputs: [() -> Producer?] = []

    func branch() -> any PreferenceScope {
        let child = PreferenceValues<K>()
        inputs.append(child.producer)
        return child
    }

    func producer() -> Producer? {
        let values = inputs.compactMap { $0() }
        guard let first = values.first else { return nil }
        return {
            var result = first()
            for next in values.dropFirst() { K.reduce(value: &result, nextValue: next) }
            return result
        }
    }
}

@MainActor private final class PreviousPreference<Value> {
    var value: Value?
}

extension Context {
    mutating func readPreference<K: PreferenceKey>(_ key: K.Type) -> () -> K.Value {
        let values = PreferenceValues<K>()
        preferences[ObjectIdentifier(key)] = values
        return { values.producer()?() ?? K.defaultValue }
    }

    mutating func publish<K: PreferenceKey>(_ key: K.Type, _ read: @escaping () -> K.Value) {
        let observer = preferences.removeValue(forKey: ObjectIdentifier(key)) as? PreferenceValues<K>
        observer?.inputs.append { read }
    }

    func preferenceBranch() -> Self {
        guard !preferences.isEmpty else { return self }
        var child = self
        child.preferences = preferences.mapValues { $0.branch() }
        return child
    }
}

extension View {
    nonisolated public func preference<K: PreferenceKey>(key: K.Type = K.self, value: K.Value) -> some View {
        deferredPreference(key) { value }
    }

    nonisolated func deferredPreference<K: PreferenceKey>(_ key: K.Type, _ read: @escaping () -> K.Value) -> some View {
        PreferenceWriter(content: self, key: key, read: read)
    }

    nonisolated public func transformPreference<K: PreferenceKey>(_ key: K.Type = K.self,
                                                      _ callback: @escaping (inout K.Value) -> Void) -> some View {
        PreferenceTransform(content: self, key: key, callback: callback)
    }

    nonisolated public func overlayPreferenceValue<K: PreferenceKey, V: View>(_ key: K.Type, alignment: Alignment = .center,
        @ContentBuilder _ transform: @escaping (K.Value) -> V) -> some View {
        PreferenceDecoration(content: self, key: key, alignment: alignment, above: true, combinesKey: true, transform: transform)
    }

    nonisolated public func backgroundPreferenceValue<K: PreferenceKey, V: View>(_ key: K.Type, alignment: Alignment = .center,
        @ContentBuilder _ transform: @escaping (K.Value) -> V) -> some View {
        PreferenceDecoration(content: self, key: key, alignment: alignment, above: false, combinesKey: true, transform: transform)
    }

    @_disfavoredOverload nonisolated public func overlayPreferenceValue<Key: PreferenceKey, T: View>(_ key: Key.Type = Key.self,
        @ContentBuilder _ transform: @escaping (Key.Value) -> T) -> some View {
        PreferenceDecoration(content: self, key: key, alignment: .center, above: true, combinesKey: false, transform: transform)
    }

    @_disfavoredOverload nonisolated public func backgroundPreferenceValue<Key: PreferenceKey, T: View>(_ key: Key.Type = Key.self,
        @ContentBuilder _ transform: @escaping (Key.Value) -> T) -> some View {
        PreferenceDecoration(content: self, key: key, alignment: .center, above: false, combinesKey: false, transform: transform)
    }

    nonisolated public func onPreferenceChange<K: PreferenceKey>(_ key: K.Type = K.self,
                                                     perform action: @escaping (K.Value) -> Void) -> some View where K.Value: Equatable {
        observePreference(key, project: { $0 }) { _, value in action(value) }
    }

    nonisolated func observePreference<K: PreferenceKey, T: Equatable>(_ key: K.Type, project: @escaping (K.Value) -> T,
                                                           action: @escaping (T?, T) -> Void) -> some View {
        PreferenceObserver(content: self, key: key, project: project, action: action)
    }
}

private nonisolated struct PreferenceWriter<Content: View, K: PreferenceKey>: View {
    let content: Content
    let key: K.Type
    let read: () -> K.Value

    @MainActor var body: some View {
        Transform(content: content) { view, context in
            var inner = context
            let parent = inner.preferences.removeValue(forKey: ObjectIdentifier(key)) as? PreferenceValues<K>
            let items = view.resolve(inner)
            if !items.isEmpty { parent?.inputs.append { read } }
            return items
        }
    }
}

private nonisolated struct PreferenceTransform<Content: View, K: PreferenceKey>: View {
    let content: Content
    let key: K.Type
    let callback: (inout K.Value) -> Void

    @MainActor var body: some View {
        Transform(content: content) { view, context in
            let id = ObjectIdentifier(key)
            guard let parent = context.preferences[id] as? PreferenceValues<K> else { return view.resolve(context) }
            var inner = context
            let child = PreferenceValues<K>()
            inner.preferences[id] = child
            let items = view.resolve(inner)
            if !items.isEmpty {
                parent.inputs.append {
                    {
                        var value = child.producer()?() ?? K.defaultValue
                        callback(&value)
                        return value
                    }
                }
            }
            return items
        }
    }
}

private nonisolated struct PreferenceDecoration<Content: View, K: PreferenceKey, V: View>: Primitive, SubviewSource {
    let content: Content
    let key: K.Type
    let alignment: Alignment
    let above: Bool
    let combinesKey: Bool
    let transform: (K.Value) -> V

    @MainActor func elements(in context: Context) -> [Element] {
        subviews(in: context).flatMap { $0.resolve(context.preferenceBranch()) }
    }

    @MainActor func subviews(in context: Context) -> [Subview] {
        content.collectSubviews(in: context).map { child in
            child.applying { view, destination in decorate(view, destination) }
        }
    }

    @MainActor private func decorate(_ view: any View, _ context: Context) -> [Element] {
        let values = PreferenceValues<K>()
        let id = ObjectIdentifier(key)
        // Reserve both branches before placement. Backgrounds reduce first, overlays last.
        let first = context.preferenceBranch()
        let second = context.preferenceBranch()
        var inner = (above ? first : second).descending(.position(0))
        var decoration = (above ? second : first).descending(.position(1))
        (inner.preferences[id] as? PreferenceValues<K>)?.inputs.append(values.producer)
        inner.preferences[id] = values
        // The older overload consumes the decoration's contribution to its own key.
        if !combinesKey { decoration.preferences.removeValue(forKey: id) }
        let base = stacked(view.resolve(inner), axis: .vertical, alignment: .center, spacing: 8)
        let background = above ? nil : decoration.widget(QSGroup)
        let result = base.wrapping(size: base.measure) { bounds, proposal in
            var target = decoration
            var area = bounds
            if let background {
                qs_place(background, bounds.minX, bounds.minY, bounds.width, bounds.height)
                target.parent = background
                area.origin = .zero
            }
            base.place(bounds, proposal)
            let offer = ProposedViewSize(bounds.size)
            let value = values.producer()?() ?? K.defaultValue
            for child in transform(value).resolve(target) {
                child.place(alignment.rect(for: child, size: child.measure(offer), proposal: offer, in: area, parent: base, parentProposal: proposal, direction: target.environment.layoutDirection), offer)
            }
        }
        return [result]
    }
}

private nonisolated struct PreferenceObserver<Content: View, K: PreferenceKey, T: Equatable>: View {
    let content: Content
    let key: K.Type
    let project: (K.Value) -> T
    let action: (T?, T) -> Void

    @MainActor var body: some View {
        Transform(content: content) { view, context in
            let id = ObjectIdentifier(key)
            let values = PreferenceValues<K>()
            (context.preferences[id] as? PreferenceValues<K>)?.inputs.append(values.producer)
            var inner = context
            inner.preferences[id] = values
            let path = context.path + [.property("onPreferenceChange"), .type(id)]
            let previous = context.host.storage[path] as? PreviousPreference<T> ?? PreviousPreference<T>()
            context.host.storage[path] = previous
            context.host.liveStorage.insert(path)
            let items = view.resolve(inner)
            context.host.afterLayout {
                let value = project(values.producer()?() ?? K.defaultValue)
                let old = previous.value
                if old != .some(value) {
                    previous.value = .some(value)
                    action(old, value)
                }
            }
            return items
        }
    }
}
