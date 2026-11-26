import QtBridge

public struct Alert {
    public struct Button {
        fileprivate let title: String?
        fileprivate let role: Int32
        fileprivate let action: (() -> Void)?

        public static func `default`(_ label: Text, action: (() -> Void)? = {}) -> Self {
            Self(title: label.string, role: 0, action: action)
        }
        public static func cancel(_ label: Text, action: (() -> Void)? = {}) -> Self {
            Self(title: label.string, role: 1, action: action)
        }
        public static func cancel(_ action: (() -> Void)? = {}) -> Self {
            Self(title: nil, role: 1, action: action)
        }
        public static func destructive(_ label: Text, action: (() -> Void)? = {}) -> Self {
            Self(title: label.string, role: 2, action: action)
        }
    }

    fileprivate let title: String
    fileprivate let message: String
    fileprivate let buttons: [Button]

    public init(title: Text, message: Text? = nil, dismissButton: Button? = nil) {
        self.title = title.string
        self.message = message?.string ?? ""
        buttons = [dismissButton ?? Button(title: nil, role: 0, action: nil)]
    }
    public init(title: Text, message: Text? = nil, primaryButton: Button, secondaryButton: Button) {
        self.title = title.string
        self.message = message?.string ?? ""
        buttons = [primaryButton, secondaryButton]
    }
}

@MainActor private final class PresentedAlert {
    let alert: Alert
    init(_ alert: Alert) { self.alert = alert }
}

private nonisolated struct AlertPresentation<Source: View, ID: Hashable>: Primitive {
    let source: Source
    let current: () -> ID?
    let alert: Alert?
    let dismiss: () -> Void

    @MainActor func elements(in context: Context) -> [Element] {
        let elements = source.resolve(context.descending(.position(0)))
        guard let id = current(), let alert, !context.host.isMeasuringAlternative else { return elements }
        let anchor = context.descending(.property("alert")).descending(.id(AnyHashable(id)))
        context.host.liveStorage.insert(anchor.path)
        let presented = context.host.storage[anchor.path] as? PresentedAlert ?? PresentedAlert(alert)
        context.host.storage[anchor.path] = presented
        let owner = anchor.widget(QSGroup, action: { value in
            guard current() == id else { return }
            dismiss()
            if let index = Int(value), presented.alert.buttons.indices.contains(index) {
                presented.alert.buttons[index].action?()
            }
        })
        qs_drawing_only(owner)
        if qs_alert_begin(owner, presented.alert.title, presented.alert.message) != 0 {
            for (index, button) in presented.alert.buttons.enumerated() {
                qs_alert_button(owner, Int32(index), button.title, button.role)
            }
            qs_alert_show(owner)
        }
        return elements
    }
}

extension View {
    nonisolated public func alert(isPresented: Binding<Bool>, content: () -> Alert) -> some View {
        AlertPresentation(source: self, current: { isPresented.wrappedValue ? true : nil }, alert: content(),
                          dismiss: { isPresented.wrappedValue = false })
    }

    nonisolated public func alert<Item: Identifiable>(item: Binding<Item?>, content: (Item) -> Alert) -> some View {
        AlertPresentation(source: self, current: { item.wrappedValue?.id }, alert: item.wrappedValue.map(content),
                          dismiss: { item.wrappedValue = nil })
    }
}
