private nonisolated struct Positioned<Content: View>: Primitive {
    let content: Content
    let point: CGPoint

    @MainActor func elements(in context: Context) -> [Element] {
        let location = context.interpolated(point.animatableData, key: "position")
        return content.resolve(context).map { child in
            let wrapper = child.wrapping { proposal in
                if let width = proposal.width, let height = proposal.height { return CGSize(width: width, height: height) }
                return proposal.replacingUnspecifiedDimensions(by: child.measure(proposal))
            } place: { bounds, proposal in
                let size = child.measure(proposal)
                let rect = CGRect(x: bounds.minX + location.first - size.width / 2,
                                  y: bounds.minY + location.second - size.height / 2, width: size.width, height: size.height)
                child.place(context.environment.layoutDirection.position(rect, in: bounds), proposal)
            }
            wrapper.sizesGroupToPositionedContent = true
            return wrapper
        }
    }
}

extension View {
    public nonisolated func position(_ position: CGPoint) -> some View { Positioned(content: self, point: position) }
    public nonisolated func position(x: CGFloat = 0, y: CGFloat = 0) -> some View { position(CGPoint(x: x, y: y)) }
}
