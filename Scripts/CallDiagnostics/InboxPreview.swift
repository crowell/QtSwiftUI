import SwiftUI

@MainActor @Observable final class InboxPreviewModel {
    var selected = NavTab.calls
    var collapsed = false
    let calls = CallsPreviewModel()
    let settings = SettingsModel()
}

struct InboxPreview: View {
    @State var model = InboxPreviewModel()

    var body: some View {
        let tabs = NavTabsState(selected: model.selected, collapsed: model.collapsed, hasPendingUpdate: true,
                                unreadCalls: model.calls.unread, onSelect: { model.selected = $0 }, onToggleCollapse: { model.collapsed = $0 })
        Inbox(navTabs: tabs) { tab in
            VStack(spacing: 0) {
                if model.collapsed && tab != .calls {
                    NavTabsToggle(collapsed: true, hasPendingUpdate: true, onToggle: { model.collapsed = $0 })
                        .frame(width: 80).frame(maxWidth: .infinity, alignment: .leading)
                }
                switch tab {
                case .calls: CallsTabPreview(model: model.calls, collapsed: model.collapsed, toggleRail: { model.collapsed = $0 })
                case .settings: SettingsPreview(calls: true, settings: model.settings)
                case .chats: EmptyChatsPreview()
                case .stories: EmptyView()
                }
            }
        }.background(AxoColor.surfacePrimary)
    }
}
