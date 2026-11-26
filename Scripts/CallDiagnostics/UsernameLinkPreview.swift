import SwiftUI
import SignalI18n
#if os(Linux)
import QtBridge
#else
import AppKit
import UniformTypeIdentifiers
#endif

@MainActor @Observable final class UsernameLinkModel {
    var color: UsernameLinkColor = .blue
    var link = UsernameCardPreview.link
    var status: UsernameLinkState = .ready
    var copy: (String) -> Void = { copyPreviewText($0) }
    var saveDestination: (String) -> URL? = { name in
        #if os(Linux)
        guard let path = qs_choose_save_path(name, "PNG image (*.png)") else { return nil }
        defer { free(path) }
        return URL(fileURLWithPath: String(cString: path))
        #else
        let panel = NSSavePanel()
        panel.nameFieldStringValue = name
        panel.allowedContentTypes = [.png]
        return panel.runModal() == .OK ? panel.url : nil
        #endif
    }
    var exportError: String?

    func save(_ color: UsernameLinkColor, i18n: Localizer) {
        let name = UsernameCardPreview.username
        guard let destination = saveDestination("\(name).png") else { return }
        guard let bytes = UsernameLinkCard.png(link: link, username: name, color: color, i18n: i18n) else {
            exportError = "Couldn’t render the username card."
            return
        }
        do { try Data(bytes).write(to: destination, options: .atomic) }
        catch { exportError = error.localizedDescription }
    }

    func reset() {
        status = .updating
        Task {
            await Task.yield()
            link = "https://signal.me/#eu/" + UUID().uuidString
            status = .ready
        }
    }
}

struct UsernameLinkPreview: View {
    @State var model = UsernameLinkModel()
    @Environment(\.i18n) var i18n

    var body: some View {
        UsernameLinkEditor(link: model.link, username: UsernameCardPreview.username,
                           usernameLinkState: model.status, color: model.color,
                           setUsernameLinkColor: { model.color = $0 }, resetUsernameLink: model.reset,
                           onSave: { model.save($0, i18n: i18n) }, copyLink: model.copy, copyUsername: model.copy)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(AxoColor.surfacePrimary)
            .overlay {
                if let error = model.exportError {
                    AxoBaseDialog.Host {
                        AxoConfirmDialog.Root(title: nil, description: error) {
                            AxoConfirmDialog.Ok(i18n("icu:ok")) { model.exportError = nil }
                        }
                    }
                }
            }
            .axoViewport()
            .axoModalHost()
    }
}
