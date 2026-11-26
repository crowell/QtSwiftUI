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

@MainActor private final class PreviousPreference<K: PreferenceKey> {
    var value: K.Value?
}

extension Context {
    func preferenceBranch() -> Self {
        guard !preferences.isEmpty else { return self }
        var child = self
        child.preferences = preferences.mapValues { $0.branch() }
        return child
    }
}

extension View {
    public func preference<K: PreferenceKey>(key: K.Type = K.self, value: K.Value) -> some View {
        Transform(content: self) { view, context in
            var inner = context
            let parent = inner.preferences.removeValue(forKey: ObjectIdentifier(key)) as? PreferenceValues<K>
            let items = view.resolve(inner)
            if !items.isEmpty { parent?.inputs.append { { value } } }
            return items
        }
    }

    public func transformPreference<K: PreferenceKey>(_ key: K.Type = K.self,
                                                      _ callback: @escaping (inout K.Value) -> Void) -> some View {
        Transform(content: self) { view, context in
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

    public func onPreferenceChange<K: PreferenceKey>(_ key: K.Type = K.self,
                                                     perform action: @escaping (K.Value) -> Void) -> some View where K.Value: Equatable {
        Transform(content: self) { view, context in
            let id = ObjectIdentifier(key)
            let values = PreferenceValues<K>()
            (context.preferences[id] as? PreferenceValues<K>)?.inputs.append(values.producer)
            var inner = context
            inner.preferences[id] = values
            let path = context.path + [.property("onPreferenceChange"), .type(id)]
            let previous = context.host.storage[path] as? PreviousPreference<K> ?? PreviousPreference<K>()
            context.host.storage[path] = previous
            context.host.liveStorage.insert(path)
            let items = view.resolve(inner)
            context.host.afterLayout {
                let value = values.producer()?() ?? K.defaultValue
                if previous.value != .some(value) {
                    previous.value = .some(value)
                    action(value)
                }
            }
            return items
        }
    }
}
