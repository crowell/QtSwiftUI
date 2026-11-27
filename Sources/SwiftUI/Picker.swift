import QtBridge

public protocol PickerStyle {}
public struct DefaultPickerStyle: PickerStyle { public init() {} }
public struct MenuPickerStyle: PickerStyle { public init() {} }
extension PickerStyle where Self == DefaultPickerStyle { public static var automatic: Self { Self() } }
extension PickerStyle where Self == MenuPickerStyle { public static var menu: Self { Self() } }

public struct InlinePickerStyle: PickerStyle { public init() {} }
extension PickerStyle where Self == InlinePickerStyle { public static var inline: Self { Self() } }
public struct SegmentedPickerStyle: PickerStyle { public init() {} }
public struct RadioGroupPickerStyle: PickerStyle { public init() {} }
extension PickerStyle where Self == SegmentedPickerStyle { public static var segmented: Self { Self() } }
extension PickerStyle where Self == RadioGroupPickerStyle { public static var radioGroup: Self { Self() } }

enum PickerPresentation: Sendable {
    case automatic, menu, inline, segmented, radioGroup
    var kind: QSKind {
        switch self {
        case .automatic, .menu: QSPicker
        case .segmented: QSSegmentedPicker
        case .inline, .radioGroup: QSRadioPicker
        }
    }
}

extension View {
    nonisolated public func pickerStyle<S: PickerStyle>(_ style: S) -> some View {
        let presentation: PickerPresentation
        switch style {
        case is SegmentedPickerStyle: presentation = .segmented
        case is RadioGroupPickerStyle: presentation = .radioGroup
        case is InlinePickerStyle: presentation = .inline
        case is MenuPickerStyle: presentation = .menu
        default: presentation = .automatic
        }
        return Transform(content: self) { $0.resolve($1.with(\.pickerPresentation, presentation)) }
    }
    nonisolated public func labelsHidden() -> some View {
        Transform(content: self) { $0.resolve($1.with(\.hidesControlLabels, true)) }
    }
}

extension Label: MenuEntrySource where Title == Text, Icon == Image {
    @MainActor func collect(in context: Context, into entries: MenuEntries) {
        entries.rows.append(.init(title: title.resolvedString(context.environment), systemImage: icon.systemName,
                                  enabled: context.collectingPickerLabels && context.environment.isEnabled))
    }
}

public nonisolated struct Picker<Label: View, SelectionValue: Hashable, Content: View>: Primitive, MenuEntrySource {
    private let bindings: [Binding<SelectionValue>]
    private let label: Label
    private let content: Content

    public init(selection: Binding<SelectionValue>, @ContentBuilder content: () -> Content, @ContentBuilder label: () -> Label) {
        bindings = [selection]
        self.label = label()
        self.content = content()
    }
    public init<C: RandomAccessCollection>(sources: C, selection: KeyPath<C.Element, Binding<SelectionValue>>,
                                           @ContentBuilder content: () -> Content, @ContentBuilder label: () -> Label) {
        bindings = sources.map { $0[keyPath: selection] }
        self.label = label()
        self.content = content()
    }

    @MainActor private func choices(in context: Context) -> (title: String, menu: MenuEntries) {
        var labels = context.descending(.property("picker options"))
        labels.parent = labels.widget(QSGroup)
        qs_drawing_only(labels.parent)
        labels.collectingPickerLabels = true
        let title = MenuEntries.title(label, in: labels)
        labels.environment.label = ""
        let selection = bindings.first.map(\.wrappedValue)
        let mixed = bindings.contains { .some($0.wrappedValue) != selection }
        let menu = MenuEntries()
        for child in content.collectSubviews(in: labels) {
            let tag = child.containerValues.tag(for: SelectionValue.self)
            let entries = MenuEntries.read(child, in: labels).rows
            let enabled = entries.contains(where: \.enabled) && tag != nil && !bindings.isEmpty
            menu.rows.append(.init(title: entries.map(\.title).joined(separator: " "),
                                   systemImage: entries.compactMap(\.systemImage).first, enabled: enabled,
                                   checked: !mixed && tag != nil && tag == selection, action: {
                guard let tag else { return }
                for binding in bindings { binding.wrappedValue = tag }
            }))
        }
        return (title, menu)
    }

    @MainActor func collect(in context: Context, into entries: MenuEntries) {
        let (title, menu) = choices(in: context)
        if context.environment.pickerPresentation == .menu {
            entries.rows.append(.init(title: title, enabled: context.environment.isEnabled, children: menu))
        } else {
            entries.rows.append(contentsOf: menu.rows)
        }
    }

    @MainActor func elements(in context: Context) -> [Element] {
        let (title, menu) = choices(in: context)
        var field = context.descending(.property("picker control"))
        field.environment.label = title
        let picker = field.widget(field.environment.pickerPresentation.kind, action: { rawIndex in
            guard let index = Int(rawIndex), menu.rows.indices.contains(index), menu.rows[index].enabled else { return }
            menu.rows[index].action?()
        })
        for (index, row) in menu.rows.enumerated() {
            qs_picker_option(picker, Int32(index), row.title, row.systemImage ?? "", row.enabled ? 1 : 0)
        }
        let selected = menu.rows.firstIndex { $0.checked == true }
        qs_picker_selection(picker, Int32(menu.rows.count), Int32(selected ?? -1))
        let control = field.control(picker)
        guard !context.environment.hidesControlLabels else { return [control] }
        let views = label.resolve(context.descending(.property("picker label")))
        return [stacked(views + [control], axis: .horizontal, alignment: .center, spacing: 8,
                        direction: context.environment.layoutDirection)]
    }
}

extension Picker where Label == SwiftUI.Label<Text, Image> {
    public init(_ titleKey: LocalizedStringKey, systemImage: String, selection: Binding<SelectionValue>, @ContentBuilder content: () -> Content) {
        self.init(selection: selection, content: content) { SwiftUI.Label(titleKey, systemImage: systemImage) }
    }
    @_disfavoredOverload public init<S: StringProtocol>(_ title: S, systemImage: String, selection: Binding<SelectionValue>, @ContentBuilder content: () -> Content) {
        self.init(selection: selection, content: content) { SwiftUI.Label(title, systemImage: systemImage) }
    }
}

extension Picker where Label == Text {
    public init(_ titleKey: LocalizedStringKey, selection: Binding<SelectionValue>, @ContentBuilder content: () -> Content) {
        self.init(selection: selection, content: content) { Text(titleKey) }
    }
    @_disfavoredOverload public init<S: StringProtocol>(_ title: S, selection: Binding<SelectionValue>, @ContentBuilder content: () -> Content) {
        self.init(selection: selection, content: content) { Text(title) }
    }
    public init<C: RandomAccessCollection>(_ titleKey: LocalizedStringKey, sources: C, selection: KeyPath<C.Element, Binding<SelectionValue>>,
                                           @ContentBuilder content: () -> Content) {
        self.init(sources: sources, selection: selection, content: content) { Text(titleKey) }
    }
    @_disfavoredOverload public init<S: StringProtocol, C: RandomAccessCollection>(_ title: S, sources: C, selection: KeyPath<C.Element, Binding<SelectionValue>>,
                                                                                  @ContentBuilder content: () -> Content) {
        self.init(sources: sources, selection: selection, content: content) { Text(title) }
    }
}
