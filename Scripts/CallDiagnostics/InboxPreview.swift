import SwiftUI

@MainActor @Observable final class InboxPreviewModel {
    var selected = NavTab.calls
    var collapsed = false
    let history = CallHistoryModel()
    let createdLink = CallLinkModel()
    let settings = SettingsModel()
}

struct InboxPreview: View {
    @State var model = InboxPreviewModel()

    var body: some View {
        let missed = model.history.history.filter(\.wasMissed).count
        let tabs = NavTabsState(selected: model.selected, collapsed: model.collapsed, hasPendingUpdate: true,
                                unreadCalls: missed, onSelect: { model.selected = $0 }, onToggleCollapse: { model.collapsed = $0 })
        Inbox(navTabs: tabs) { tab in
            VStack(spacing: 0) {
                if model.collapsed {
                    NavTabsToggle(collapsed: true, hasPendingUpdate: true, onToggle: { model.collapsed = $0 })
                        .frame(width: 80).frame(maxWidth: .infinity, alignment: .leading)
                }
                switch tab {
                case .calls: CallHistoryBrowserPreview(history: model.history, created: model.createdLink)
                case .settings: SettingsPreview(calls: true, settings: model.settings)
                case .chats: EmptyChatsPreview()
                case .stories: EmptyView()
                }
            }
        }.background(AxoColor.surfacePrimary)
    }
}
