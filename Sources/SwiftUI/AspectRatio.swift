public enum ContentMode: Hashable, CaseIterable, Sendable {
    case fit, fill
}

private nonisolated struct AspectRatioView<Content: View>: Primitive {
    let content: Content
    let aspectRatio: CGFloat?
    let contentMode: ContentMode

    @MainActor func elements(in context: Context) -> [Element] {
        content.resolve(context).map { child in
            @MainActor func offer(_ proposal: ProposedViewSize) -> ProposedViewSize {
                let ratio: CGFloat
                if let aspectRatio { ratio = aspectRatio }
                else {
                    let ideal = child.measure(.unspecified)
                    ratio = ideal.width / ideal.height
                }
                guard ratio.isFinite, ratio > 0 else { return proposal }
                switch (proposal.width, proposal.height) {
                case (nil, nil): return .unspecified
                case (let width?, nil): return .init(width: width, height: width / ratio)
                case (nil, let height?): return .init(width: height * ratio, height: height)
                case (let width?, let height?):
                    let fromWidth = width / ratio
                    if (contentMode == .fit && fromWidth <= height) || (contentMode == .fill && fromWidth >= height) {
                        return .init(width: width, height: fromWidth)
                    }
                    return .init(width: height * ratio, height: height)
                }
            }
            return child.wrapping { child.measure(offer($0)) } place: { bounds, proposal in
                child.place(bounds, offer(proposal))
            }
        }
    }
}

extension View {
    public nonisolated func aspectRatio(_ aspectRatio: CGFloat? = nil, contentMode: ContentMode) -> some View {
        AspectRatioView(content: self, aspectRatio: aspectRatio, contentMode: contentMode)
    }

    public nonisolated func aspectRatio(_ aspectRatio: CGSize, contentMode: ContentMode) -> some View {
        self.aspectRatio(aspectRatio.width / aspectRatio.height, contentMode: contentMode)
    }

    public nonisolated func scaledToFit() -> some View { aspectRatio(contentMode: .fit) }
    public nonisolated func scaledToFill() -> some View { aspectRatio(contentMode: .fill) }
}
