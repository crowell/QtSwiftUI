/// Backed by the same mounted state as a view property so editing a presentation
/// value invalidates that window and changes the value used to find it.
@MainActor final class WindowPresentation {
    private var storage: State<AnyHashable?>
    var value: AnyHashable? { storage.wrappedValue }

    init(_ value: AnyHashable?) { storage = State(wrappedValue: value) }

    func binding(in context: Context) -> Binding<AnyHashable?> {
        storage.install(in: context.descending(.property("window presentation value")))
        return storage.projectedValue
    }
}

public nonisolated struct PresentedWindowContent<Data: Codable & Hashable, Content: View>: Primitive {
    fileprivate let build: (Binding<AnyHashable?>) -> Content

    @MainActor func elements(in context: Context) -> [Element] {
        guard let binding = context.windowValue else { return [] }
        return build(binding).resolve(context)
    }
}

extension WindowGroup {
    private init<D: Codable & Hashable, C: View>(title: String, id: String?, type: D.Type,
                                                 optionalContent: @escaping (Binding<D?>) -> C)
    where Content == PresentedWindowContent<D, C> {
        self.init(title: title, id: id, valueType: ObjectIdentifier(type)) {
            PresentedWindowContent { source in
                optionalContent(Binding(get: { source.wrappedValue?.base as? D },
                                        set: { source.wrappedValue = $0.map(AnyHashable.init) }))
            }
        }
    }

    private init<D: Codable & Hashable, C: View>(title: String, id: String?, type: D.Type,
                                                 content: @escaping (Binding<D>) -> C, defaultValue: @escaping () -> D)
    where Content == PresentedWindowContent<D, C> {
        self.init(title: title, id: id, valueType: ObjectIdentifier(type), initialValue: { AnyHashable(defaultValue()) }) {
            PresentedWindowContent { source in
                // Every new instance starts with either a type-matched request or its default value.
                content(Binding(get: { source.wrappedValue?.base as? D ?? defaultValue() },
                                set: { source.wrappedValue = AnyHashable($0) }))
            }
        }
    }

    public init<D: Codable & Hashable, C: View>(for type: D.Type,
        @ContentBuilder content: @escaping (Binding<D?>) -> C)
    where Content == PresentedWindowContent<D, C> {
        self.init(title: "", id: nil, type: type, optionalContent: content)
    }

    public init<D: Codable & Hashable, C: View>(_ title: Text, for type: D.Type,
        @ContentBuilder content: @escaping (Binding<D?>) -> C)
    where Content == PresentedWindowContent<D, C> {
        self.init(title: title.string, id: nil, type: type, optionalContent: content)
    }

    public init<S: StringProtocol, D: Codable & Hashable, C: View>(_ title: S, for type: D.Type,
        @ContentBuilder content: @escaping (Binding<D?>) -> C)
    where Content == PresentedWindowContent<D, C> {
        self.init(title: String(title), id: nil, type: type, optionalContent: content)
    }

    public init<D: Codable & Hashable, C: View>(id: String, for type: D.Type,
        @ContentBuilder content: @escaping (Binding<D?>) -> C)
    where Content == PresentedWindowContent<D, C> {
        self.init(title: "", id: id, type: type, optionalContent: content)
    }

    public init<D: Codable & Hashable, C: View>(_ title: Text, id: String, for type: D.Type,
        @ContentBuilder content: @escaping (Binding<D?>) -> C)
    where Content == PresentedWindowContent<D, C> {
        self.init(title: title.string, id: id, type: type, optionalContent: content)
    }

    public init<S: StringProtocol, D: Codable & Hashable, C: View>(_ title: S, id: String, for type: D.Type,
        @ContentBuilder content: @escaping (Binding<D?>) -> C)
    where Content == PresentedWindowContent<D, C> {
        self.init(title: String(title), id: id, type: type, optionalContent: content)
    }

    public init<D: Codable & Hashable, C: View>(for type: D.Type = D.self,
        @ContentBuilder content: @escaping (Binding<D>) -> C, defaultValue: @escaping () -> D)
    where Content == PresentedWindowContent<D, C> {
        self.init(title: "", id: nil, type: type, content: content, defaultValue: defaultValue)
    }

    public init<D: Codable & Hashable, C: View>(_ title: Text, for type: D.Type = D.self,
        @ContentBuilder content: @escaping (Binding<D>) -> C, defaultValue: @escaping () -> D)
    where Content == PresentedWindowContent<D, C> {
        self.init(title: title.string, id: nil, type: type, content: content, defaultValue: defaultValue)
    }

    public init<S: StringProtocol, D: Codable & Hashable, C: View>(_ title: S, for type: D.Type = D.self,
        @ContentBuilder content: @escaping (Binding<D>) -> C, defaultValue: @escaping () -> D)
    where Content == PresentedWindowContent<D, C> {
        self.init(title: String(title), id: nil, type: type, content: content, defaultValue: defaultValue)
    }

    public init<D: Codable & Hashable, C: View>(id: String, for type: D.Type = D.self,
        @ContentBuilder content: @escaping (Binding<D>) -> C, defaultValue: @escaping () -> D)
    where Content == PresentedWindowContent<D, C> {
        self.init(title: "", id: id, type: type, content: content, defaultValue: defaultValue)
    }

    public init<D: Codable & Hashable, C: View>(_ title: Text, id: String, for type: D.Type = D.self,
        @ContentBuilder content: @escaping (Binding<D>) -> C, defaultValue: @escaping () -> D)
    where Content == PresentedWindowContent<D, C> {
        self.init(title: title.string, id: id, type: type, content: content, defaultValue: defaultValue)
    }

    public init<S: StringProtocol, D: Codable & Hashable, C: View>(_ title: S, id: String, for type: D.Type = D.self,
        @ContentBuilder content: @escaping (Binding<D>) -> C, defaultValue: @escaping () -> D)
    where Content == PresentedWindowContent<D, C> {
        self.init(title: String(title), id: id, type: type, content: content, defaultValue: defaultValue)
    }
}
