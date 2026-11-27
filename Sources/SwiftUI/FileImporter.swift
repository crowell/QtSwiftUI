import Foundation
import QtBridge
import UniformTypeIdentifiers

private extension EnvironmentValues {
    @Entry var fileDialogCustomizationID: String?
    @Entry var fileDialogMessage: Text?
    @Entry var fileDialogConfirmationLabel: Text?
}

private nonisolated struct FileImporter<Source: View>: Primitive {
    let source: Source
    let isPresented: Binding<Bool>
    let types: [UTType]
    let multiple: Bool
    let complete: (Result<[URL], any Error>) -> Void
    let cancel: () -> Void

    @MainActor func elements(in context: Context) -> [Element] {
        let elements = source.resolve(context.descending(.position(0)))
        guard isPresented.wrappedValue, !context.host.isMeasuringAlternative else { return elements }
        let anchor = context.descending(.property("fileImporter"))
        let owner = anchor.widget(QSGroup, action: { value in
            guard isPresented.wrappedValue else { return }
            isPresented.wrappedValue = false
            if value == "cancel" { cancel(); return }
            let entries = value.split(separator: "\n")
            let urls = entries.compactMap { URL(string: String($0)) }
            guard !urls.isEmpty, urls.count == entries.count else {
                complete(.failure(CocoaError(.fileReadUnknown)))
                return
            }
            complete(.success(urls))
        })
        qs_drawing_only(owner)
        let files = types.filter { !$0.conforms(to: .directory) }
        let directories: Int32 = files.count == types.count ? 0 : files.isEmpty ? 1 : 2
        let filters = files.map { type in
            if type == .image { return "image/*" }
            if type == .text { return "text/*" }
            if type == .data { return "*" }
            return type.preferredMIMEType?.components(separatedBy: ";").first ?? "*"
        }
        let key = context.environment.fileDialogCustomizationID.map { "QtSwiftUI.fileDialog." + Data($0.utf8).base64EncodedString() }
        qs_file_import(owner, filters.joined(separator: "\n"), directories, multiple ? 1 : 0,
                       context.environment.fileDialogDirectory?.path,
                       context.environment.fileDialogMessage?.resolvedString(context.environment),
                       context.environment.fileDialogConfirmationLabel?.resolvedString(context.environment),
                       key, key.flatMap(UserDefaults.standard.string(forKey:))) { key, state in
            guard let key, let state else { return }
            UserDefaults.standard.set(String(cString: state), forKey: String(cString: key))
            UserDefaults.standard.synchronize()
        }
        return elements
    }
}

extension View {
    nonisolated public func fileImporter(isPresented: Binding<Bool>, allowedContentTypes: [UTType],
                                         onCompletion: @escaping (_ result: Result<URL, any Error>) -> Void) -> some View {
        FileImporter(source: self, isPresented: isPresented, types: allowedContentTypes, multiple: false,
                     complete: { onCompletion($0.flatMap { urls in
                         guard let url = urls.first else { return .failure(CocoaError(.fileReadUnknown)) }
                         return .success(url)
                     }) }, cancel: {})
    }

    nonisolated public func fileImporter(isPresented: Binding<Bool>, allowedContentTypes: [UTType], allowsMultipleSelection: Bool,
                                         onCompletion: @escaping (_ result: Result<[URL], any Error>) -> Void) -> some View {
        fileImporter(isPresented: isPresented, allowedContentTypes: allowedContentTypes,
                     allowsMultipleSelection: allowsMultipleSelection, onCompletion: onCompletion, onCancellation: {})
    }

    nonisolated public func fileImporter(isPresented: Binding<Bool>, allowedContentTypes: [UTType], allowsMultipleSelection: Bool,
                                         onCompletion: @escaping (_ result: Result<[URL], any Error>) -> Void,
                                         onCancellation: @escaping () -> Void) -> some View {
        FileImporter(source: self, isPresented: isPresented, types: allowedContentTypes, multiple: allowsMultipleSelection,
                     complete: onCompletion, cancel: onCancellation)
    }

    nonisolated public func fileDialogCustomizationID(_ id: String) -> some View {
        environment(\.fileDialogCustomizationID, id)
    }

    nonisolated public func fileDialogMessage(_ message: Text?) -> some View {
        environment(\.fileDialogMessage, message)
    }
    nonisolated public func fileDialogMessage(_ messageKey: LocalizedStringKey) -> some View {
        fileDialogMessage(Text(messageKey))
    }
    @_disfavoredOverload nonisolated public func fileDialogMessage<S>(_ message: S) -> some View where S: StringProtocol {
        fileDialogMessage(Text(verbatim: String(message)))
    }
    nonisolated public func fileDialogConfirmationLabel(_ label: Text?) -> some View {
        environment(\.fileDialogConfirmationLabel, label)
    }
    nonisolated public func fileDialogConfirmationLabel(_ labelKey: LocalizedStringKey) -> some View {
        fileDialogConfirmationLabel(Text(labelKey))
    }
    @_disfavoredOverload nonisolated public func fileDialogConfirmationLabel<S>(_ label: S) -> some View where S: StringProtocol {
        fileDialogConfirmationLabel(Text(verbatim: String(label)))
    }

    nonisolated public func fileDialogDefaultDirectory(_ defaultDirectory: URL?) -> some View {
        Transform(content: self) { view, context in view.resolve(context.with(\.fileDialogDirectory, defaultDirectory)) }
    }
}
