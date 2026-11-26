import QtBridge

extension View {
    nonisolated public func blur(radius: CGFloat, opaque: Bool = false) -> some View {
        Transform(content: self) { view, ctx in
            let group = ctx.widget(QSGroup)
            qs_view_blur(group, ctx.interpolated(radius, key: "blur"), opaque ? 1 : 0)
            return ctx.children(of: view, inside: group)
        }
    }

    nonisolated public func hidden() -> some View {
        Transform(content: self) { view, ctx in
            let group = ctx.widget(QSGroup)
            qs_drawing_only(group)
            var inner = ctx.descending(.position(0))
            inner.parent = group
            // Place each child in its parent's coordinate system. Logical groups can have
            // multiple layout children even though all of their widgets are invisible.
            qs_place(group, 0, 0, 0, 0)
            return view.resolve(inner)
        }
    }

    nonisolated public func mask<Mask: View>(_ mask: Mask) -> some View {
        self.mask(alignment: .center) { mask }
    }

    nonisolated public func mask<Mask: View>(alignment: Alignment = .center, @ContentBuilder _ mask: () -> Mask) -> some View {
        let maskView = mask()
        return Transform(content: self) { view, ctx in
            let group = ctx.widget(QSGroup)
            var contentContext = ctx.descending(.position(0))
            contentContext.parent = group
            let content = stacked(view.resolve(contentContext), axis: .vertical, alignment: .center, spacing: 8)
            var maskContext = ctx.descending(.position(1))
            let stencil = maskContext.widget(QSGroup)
            qs_drawing_only(stencil)
            maskContext.parent = stencil
            let drawing = stacked(maskView.resolve(maskContext), axis: .vertical, alignment: .center, spacing: 8)
            return [content.wrapping(size: content.measure) { bounds, proposal in
                let local = CGRect(origin: .zero, size: bounds.size)
                let maskProposal = ProposedViewSize(bounds.size)
                qs_place(stencil, bounds.minX, bounds.minY, bounds.width, bounds.height)
                drawing.place(alignment.rect(drawing.measure(maskProposal), in: local, direction: ctx.environment.layoutDirection), maskProposal)
                qs_place(group, bounds.minX, bounds.minY, bounds.width, bounds.height)
                content.place(local, proposal)
                qs_alpha_mask(group, stencil)
            }]
        }
    }
}
