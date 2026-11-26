import SwiftUI

@MainActor @Observable final class ChatFoldersModel {
    var folders = [
        ChatFolder(id: "all", folderType: .all, position: 0),
        ChatFolder(id: "ferry", folderType: .custom, name: "Ferry crew", position: 1),
        ChatFolder(id: "family", folderType: .custom, name: "Family", position: 2)
    ]
    var editing = false
    var editID: String?
    var name = ""

    func add(_ name: String, _ preset: ChatFolderPreset) {
        folders.append(ChatFolder(id: UUID().uuidString, folderType: .custom, name: name, position: (folders.map(\.position).max() ?? -1) + 1, preset: preset))
    }
    func reorder(_ ids: [String]) {
        for i in folders.indices {
            if let position = ids.firstIndex(of: folders[i].id) { folders[i].position = position }
        }
    }
    func beginEdit(_ id: String?) {
        editID = id
        name = folders.first { $0.id == id }?.name ?? ""
        editing = true
    }
    func save() {
        if let index = folders.firstIndex(where: { $0.id == editID }) { folders[index].name = name }
        else { add(name, .defaults) }
        editing = false
    }
}

struct ChatFoldersPreview: View {
    @State var model = ChatFoldersModel()
    @Environment(\.dismiss) var dismiss
    var body: some View {
        @Bindable var model = model
        ZStack {
            PreferencesChatFoldersPage(chatFolders: model.folders, onBack: { dismiss() },
                                       onOpenEditChatFoldersPage: model.beginEdit, onCreateChatFolder: model.add,
                                       onDeleteChatFolder: { id in model.folders.removeAll { $0.id == id } },
                                       onUpdateChatFoldersPositions: model.reorder)
            if model.editing {
                // A local destination for the production page's edit callback.
                AxoBaseDialog.Host {
                    AxoAlertDialog.Content {
                        AxoAlertDialog.Body {
                            AxoAlertDialog.Title("Folder name")
                            TextField("Name", text: $model.name)
                        }
                        AxoAlertDialog.Footer {
                            AxoAlertDialog.Cancel("Cancel") { model.editing = false }
                            AxoAlertDialog.Action("Save", variant: .strongPrimary, action: model.save).disabled(model.name.isEmpty)
                        }
                    }
                }
            }
        }
        .axoLayerHost()
        .axoViewport()
        .background(AxoColor.surfacePrimary)
    }
}
