struct ScrollVisibilitySnapshot {
    struct Entry {
        let id: AnyHashable
        let rect: CGRect
    }
    let entries: [Entry]
    let viewport: CGRect

    func visible<ID: Hashable>(as type: ID.Type, threshold: Double) -> [ID] {
        entries.compactMap { entry in
            guard let id = entry.id.base as? ID else { return nil }
            let visible = entry.rect.intersection(viewport)
            guard !visible.isEmpty, !visible.isNull, !entry.rect.isEmpty else { return nil }
            let fraction = visible.width * visible.height / (entry.rect.width * entry.rect.height)
            return fraction >= threshold ? id : nil
        }
    }
}

enum FirstScrollVisibility: PreferenceKey {
    static var defaultValue: ScrollVisibilitySnapshot? { nil }
    static func reduce(value: inout ScrollVisibilitySnapshot?, nextValue: () -> ScrollVisibilitySnapshot?) {
        if value == nil { value = nextValue() }
    }
}

private nonisolated struct TargetVisibilityObserver<Content: View, ID: Hashable>: View {
    let content: Content
    let type: ID.Type
    let threshold: Double
    let action: ([ID]) -> Void

    @MainActor var body: some View {
        content.observePreference(FirstScrollVisibility.self, project: { $0?.visible(as: type, threshold: threshold) }) { _, ids in
            if let ids { action(ids) }
        }
    }
}

extension View {
    nonisolated public func scrollTargetLayout(isEnabled: Bool = true) -> some View {
        Transform(content: self) { content, context in
            var inner = context
            inner.isScrollTargetLayout = isEnabled
            return content.resolve(inner)
        }
    }

    nonisolated public func onScrollTargetVisibilityChange<ID>(idType: ID.Type, threshold: Double = 0.5,
                                                              _ action: @escaping ([ID]) -> Void) -> some View where ID: Hashable {
        TargetVisibilityObserver(content: self, type: idType, threshold: threshold, action: action)
    }
}
