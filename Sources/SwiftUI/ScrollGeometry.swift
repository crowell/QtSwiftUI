public struct ScrollGeometry: Equatable, Sendable, CustomDebugStringConvertible {
    public var contentOffset: CGPoint
    public var contentSize: CGSize
    public var contentInsets: EdgeInsets
    public var containerSize: CGSize
    public var bounds: CGRect { CGRect(origin: contentOffset, size: containerSize) }
    public var visibleRect: CGRect { bounds }

    public init(contentOffset: CGPoint, contentSize: CGSize, contentInsets: EdgeInsets, containerSize: CGSize) {
        self.contentOffset = contentOffset
        self.contentSize = contentSize
        self.contentInsets = contentInsets
        self.containerSize = containerSize
    }

    public var debugDescription: String {
        let i = contentInsets
        return "<ScrollGeometry: contentOffset (\(contentOffset.x), \(contentOffset.y)), " +
            "contentSize (\(contentSize.width), \(contentSize.height)), " +
            "contentInsets <top: \(i.top), leading: \(i.leading), bottom: \(i.bottom), trailing: \(i.trailing)>, " +
            "containerSize (\(containerSize.width), \(containerSize.height)), " +
            "visibleRect (\(visibleRect.minX), \(visibleRect.minY), \(visibleRect.width), \(visibleRect.height))>"
    }
}

enum FirstScrollGeometry: PreferenceKey {
    static let defaultValue: ScrollGeometry? = nil
    static func reduce(value: inout ScrollGeometry?, nextValue: () -> ScrollGeometry?) {
        if value == nil { value = nextValue() }
    }
}

extension View {
    public func onScrollGeometryChange<T: Equatable>(for type: T.Type, of transform: @escaping (ScrollGeometry) -> T,
                                                     action: @escaping (_ oldValue: T, _ newValue: T) -> Void) -> some View {
        observePreference(FirstScrollGeometry.self, project: { $0.map(transform) }) { old, next in
            if let next { action(old.flatMap { $0 } ?? next, next) }
        }
    }
}
