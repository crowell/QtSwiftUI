import SwiftUI
import SignalI18n

@main
struct DiagnosticPreview: App {
    @State private var showingShortcuts = CommandLine.arguments.contains("--shortcut-guide")
    var body: some Scene {
        let linkError = CommandLine.arguments.contains("--link-error")
        let linking = linkError || CommandLine.arguments.contains("--link-device")
        let leaveCall = CommandLine.arguments.contains("--leave-call")
        let clearing = CommandLine.arguments.contains("--clearing-data")
        let callsTab = CommandLine.arguments.contains("--calls-tab")
        let desktopMenus = CommandLine.arguments.contains("--shortcut-guide") || CommandLine.arguments.contains("--desktop-menus")
        let inbox = desktopMenus || CommandLine.arguments.contains("--inbox")
        let request = CommandLine.arguments.contains("--join-request")
        let appAbout = CommandLine.arguments.contains("--about")
        let about = CommandLine.arguments.contains("--about-contact")
        let note = CommandLine.arguments.contains("--note-preview")
        let linkDetails = CommandLine.arguments.contains("--call-link")
        let nickname = CommandLine.arguments.contains("--nickname")
        let history = CommandLine.arguments.contains("--call-history")
        let calls = CommandLine.arguments.contains("--call-settings")
        let settings = calls || CommandLine.arguments.contains("--data-usage-settings")
        let survey = CommandLine.arguments.contains("--call-survey")
        let colorPicker = CommandLine.arguments.contains("--color-picker")
        let colorEditor = CommandLine.arguments.contains("--color-editor")
        let typing = CommandLine.arguments.contains("--typing")
        let conversation = typing || CommandLine.arguments.contains("--conversation")
        let timeline = CommandLine.arguments.contains("--timeline")
        let muteUntil = CommandLine.arguments.contains("--mute-until")
        let usernameEditor = CommandLine.arguments.contains("--username-link")
        let usernameCard = CommandLine.arguments.contains("--username-card")
        let screenShare = CommandLine.arguments.contains("--share-picker")
        let stickers = CommandLine.arguments.contains("--stickers")
        let timer = CommandLine.arguments.contains("--disappearing-timer")
        let photoViewer = CommandLine.arguments.contains("--lightbox")
        let populatedGallery = CommandLine.arguments.contains("--gallery-media")
        let gallery = populatedGallery || CommandLine.arguments.contains("--gallery")
        let draft = CommandLine.arguments.contains("--recording-draft")
        let recording = CommandLine.arguments.contains("--recording")
        let discard = CommandLine.arguments.contains("--discard-recording")
        let arabic = CommandLine.arguments.contains("--arabic")
        WindowGroup(typing ? "Ferry crew" : conversation ? "Nyah Stroman" : timeline ? "Conversation timeline" : muteUntil ? "Mute until" : usernameEditor ? "Username link" : usernameCard ? "Username QR card" : screenShare ? "Share your screen" : stickers ? "Stickers" : timer ? "Disappearing messages" : photoViewer ? "Photo" : callsTab ? "Calls" : inbox ? "Inbox" : appAbout ? "About" : about ? "About contact" : note ? "Contact note" : request ? "Request to join" : linkDetails ? "Call link" : nickname ? "Edit nickname and note" : history ? "Call history" : settings ? (calls ? "Calls" : "Data usage") : survey ? "Call quality" : colorPicker ? "Chat color" : colorEditor ? "Custom chat color" : recording || draft || discard ? "Voice message" : gallery ? "All media" : clearing ? "Clearing data" : linking ? "Link device" : leaveCall ? "Leave current call" : "Call diagnostics") {
            if conversation {
                ConversationPreview(model: .init(groupTyping: typing))
                    .environment(\.axoAnimationsDisabled, CommandLine.arguments.contains("--still"))
            }
            else if timeline { TimelinePreview() }
            else if muteUntil { MuteUntilPreview() }
            else if usernameEditor { UsernameLinkPreview() }
            else if usernameCard { UsernameCardPreview() }
            else if screenShare { ScreenSharePreview() }
            else if stickers { StickerPreview() }
            else if timer { DisappearingTimerPreview() }
            else if photoViewer { PhotoPreview() }
            else if callsTab { CallsTabPreview() }
            else if desktopMenus {
                ZStack {
                    InboxPreview()
                    if showingShortcuts { ShortcutGuideModal(platform: "linux") { showingShortcuts = false } }
                }
            }
            else if inbox { InboxPreview() }
            else if request || about || note { ContactFlowPreview(model: .init(start: request ? .request : about ? .about : .note)) }
            else if appAbout { AppAboutPreview() }
            else if linkDetails { CallLinkPreview() }
            else if nickname { NicknamePreview() }
            else if history { CallHistoryBrowserPreview() }
            else if settings { SettingsPreview(calls: calls) }
            else if survey { CallSurveyPreview() }
            else if colorPicker { ChatColorPickerPreview() }
            else if colorEditor { ColorEditorPreview() }
            else if draft { RecordingDraftPreview() }
            else if recording || discard { RecordingPreview(discard: discard) }
            else if gallery { GalleryPreview(populated: populatedGallery) }
            else if clearing {
                ClearingData(step: .deletingData)
                    .background(AxoColor.surfacePrimary)
                    .environment(\.layoutDirection, arabic ? .rightToLeft : .leftToRight)
                    .environment(\.i18n, Localizer(locale: arabic ? "ar" : "en"))
                    .environment(\.axoAnimationsDisabled, CommandLine.arguments.contains("--still"))
            } else if linking { DeviceLinkPreview(showError: linkError) }
            else if leaveCall { LeaveCallPreview() }
            else { DiagnosticContent() }
        }
        .commands {
            if desktopMenus {
                CommandMenu(MainMenu.displayLabel(DefaultLocalizer.english("icu:mainMenuHelp"))) {
                    Button(MainMenu.displayLabel(DefaultLocalizer.english("icu:helpMenuShowKeyboardShortcuts"))) { showingShortcuts = true }
                        .keyboardShortcut("/", modifiers: .control)
                }
            }
        }
        .defaultSize(width: conversation || timeline ? 560 : muteUntil ? 640 : usernameCard ? 424 : screenShare ? 840 : stickers ? 600 : photoViewer ? 760 : callsTab ? 760 : inbox ? 840 : linkDetails ? 620 : nickname ? 520 : history ? 360 : settings ? 640 : colorPicker ? 780 : recording || draft ? 640 : linking || clearing ? 680 : 520,
                     height: desktopMenus ? 660 : conversation ? 502 : timeline ? 450 : muteUntil ? 600 : usernameEditor ? 540 : usernameCard ? 576 : screenShare ? 620 : stickers ? 460 : photoViewer ? 560 : callsTab || inbox ? 520 : about ? 620 : note ? 380 : request ? 510 : linkDetails ? 620 : nickname ? 560 : history ? 418 : settings ? 567 : survey ? 600 : colorPicker ? 720 : colorEditor ? 620 : recording || draft ? 84 : discard ? 280 : linking || clearing ? 420 : 440)
    }
}

struct AppAboutPreview: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        About(appEnv: "development", platform: "linux", version: "QtSwiftUI preview", closeAbout: { dismiss() })
    }
}

struct DisappearingTimerPreview: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        AxoBaseDialog.Host {
            DisappearingTimeDialog(initialValue: 45 * 60, onClose: { dismiss() })
        }
        .background(AxoColor.surfacePrimary)
    }
}

struct ColorEditorPreview: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        AxoBaseDialog.Host {
            CustomColorEditorDialog(initialGradient: (start: 0xB36409, end: 0x852CB1, angle: 135), onClose: { dismiss() })
        }
        .background(AxoColor.surfacePrimary)
        .environment(\.conversationListNow, Date(timeIntervalSince1970: 1_793_793_600))
        .environment(\.timeZone, TimeZone(secondsFromGMT: 0)!)
    }
}

struct RecordingDraftPreview: View {
    @Environment(\.dismiss) private var dismiss
    @State private var position = 32.0
    @State private var playStart: Date?
    private let duration = 83.0

    private func time(at date: Date) -> Double {
        min(duration, position + (playStart.map { max(0, date.timeIntervalSince($0)) } ?? 0))
    }
    var body: some View {
        TimelineView(.animation(minimumInterval: 0.1, paused: playStart == nil)) { clock in
            let playback = time(at: clock.date)
            CompositionRecordingDraft(peaks: RecordingPreview.peaks.map { $0.value / 255 }, duration: duration,
                active: .init(playing: playStart != nil && playback < duration, duration: duration, currentTime: playback),
                onCancel: { dismiss() }, onSend: { dismiss() },
                onPlay: { if position >= duration { position = 0 }; playStart = .now },
                onPause: { position = time(at: .now); playStart = nil },
                onScrub: { ratio in position = ratio * duration; if playStart != nil { playStart = .now } })
                .onChange(of: playback >= duration) { _, ended in
                    if ended { position = duration; playStart = nil }
                }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AxoColor.surfacePrimary)
    }
}

struct RecordingPreview: View {
    let discard: Bool
    @Environment(\.dismiss) var dismiss
    @State private var start = Date.now.addingTimeInterval(-83)
    static let peaks: [RecordingPeak] = (0..<64).map { index in
        let envelope = abs(sin(Double(index) / 8) * cos(Double(index) / 3))
        return RecordingPeak(value: 15 + envelope * 200, index: index)
    }
    var body: some View {
        Group {
            if discard {
                AxoBaseDialog.Host {
                    DiscardDraftDialog(onClose: { dismiss() }, onDiscard: { dismiss() })
                }
            } else {
                CompositionRecording(peaks: Self.peaks, startedAt: start, onCancel: { dismiss() }, onSend: { dismiss() })
                    .environment(\.conversationListNow, start.addingTimeInterval(83))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AxoColor.surfacePrimary)
    }
}

struct GalleryPreview: View {
    var populated = false
    @State private var attachments = GalleryMediaSample.attachments
    @State private var opened: PhotoPreviewModel?
    @State private var tab: MediaGalleryTab = .media
    @State private var order: MediaSortOrder = .date
    @Environment(\.dismiss) var dismiss
    var body: some View {
        if let opened {
            PhotoPreview(model: opened, close: { self.opened = nil })
        } else {
            GalleryPanel(tab: $tab, order: $order, onBack: { dismiss() }, attachments: populated ? attachments : []) { index in
                switch attachments[index].status {
                case .readyToShow:
                    let available = attachments.indices.filter { attachments[$0].image != nil }
                    if let selected = available.firstIndex(of: index) {
                        let media = available.map { LightboxMediaItem(kind: .image, image: attachments[$0].image, thumbnail: attachments[$0].image) }
                        opened = PhotoPreviewModel(media: media, selected: selected)
                    }
                case .needsDownload, .downloading: attachments[index].pending.toggle()
                }
            }
        }
    }
}

struct GalleryPanel: View {
    @Binding var tab: MediaGalleryTab
    @Binding var order: MediaSortOrder
    var onBack: () -> Void
    var attachments: [MessageAttachment] = []
    var onItemClick: (Int) -> Void = { _ in }

    var body: some View {
        ConversationPanel(onBack: onBack) {
            MediaGalleryPanelHeader(tab: $tab, sortOrder: $order)
        } content: {
            if tab == .media && !attachments.isEmpty {
                ScrollView { GalleryMediaSection(attachments: attachments, order: order, onClick: onItemClick) }
            } else { MediaGalleryEmptyState(tab: tab) }
        }
        .axoLayerHost()
    }
}

struct DeviceLinkPreview: View {
    @State private var showError: Bool

    init(showError: Bool) { _showError = State(initialValue: showError) }

    var body: some View {
        if showError {
            InstallScreenErrorStep(error: .connectionFailed, tryAgain: { showError = false })
        } else {
            InstallScreenLinkInProgressStep()
        }
    }
}

struct LeaveCallPreview: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        AxoBaseDialog.Host {
            ConfirmLeaveCallModal(onCancel: { dismiss() }, leaveCurrentCallAndStartCallingLobby: { dismiss() })
        }
        .background(AxoColor.surfacePrimary)
    }
}

struct DiagnosticContent: View {
    @Environment(\.dismiss) private var dismiss

    // The production formatter expands the JSON string inside rawStatsText.
    static let report = #"""
    {
      "callState": "Connected",
      "durationSeconds": 187,
      "rawStatsText": "{\"audio\":{\"codec\":\"opus\",\"jitterMs\":4,\"packetsLost\":0},\"connection\":{\"roundTripTimeMs\":28,\"transport\":\"udp\"},\"video\":{\"codec\":\"VP9\",\"framesPerSecond\":30,\"height\":720,\"width\":1280}}"
    }
    """#

    var body: some View {
        CallDiagnosticWindow(diagnosticData: Self.report) { dismiss() }
    }
}
