public nonisolated struct Label<Title: View, Icon: View>: View {
    let title: Title
    let icon: Icon
    public init(@ViewBuilder title: () -> Title, @ViewBuilder icon: () -> Icon) {
        self.title = title()
        self.icon = icon()
    }
    public init<S: StringProtocol>(_ title: S, systemImage name: String) where Title == Text, Icon == Image {
        self.title = Text(title)
        icon = Image(systemName: name)
    }
    @MainActor public var body: some View {
        HStack(spacing: 6) { icon.accessibilityHidden(true); title }
            .accessibilityElement(children: .combine)
    }
}

extension Button where Label == SwiftUI.Label<Text, Image> {
    public init<S: StringProtocol>(_ title: S, systemImage: String, action: @escaping @MainActor () -> Void) {
        self.init(action: action) { SwiftUI.Label(title, systemImage: systemImage) }
    }
}
