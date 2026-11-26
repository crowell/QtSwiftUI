import SwiftUI
import SignalI18n

@main
struct DiagnosticPreview: App {
    var body: some Scene {
        let linkError = CommandLine.arguments.contains("--link-error")
        let linking = linkError || CommandLine.arguments.contains("--link-device")
        let leaveCall = CommandLine.arguments.contains("--leave-call")
        let clearing = CommandLine.arguments.contains("--clearing-data")
        let gallery = CommandLine.arguments.contains("--gallery")
        let draft = CommandLine.arguments.contains("--recording-draft")
        let recording = CommandLine.arguments.contains("--recording")
        let discard = CommandLine.arguments.contains("--discard-recording")
        let arabic = CommandLine.arguments.contains("--arabic")
        WindowGroup(recording || draft || discard ? "Voice message" : gallery ? "All media" : clearing ? "Clearing data" : linking ? "Link device" : leaveCall ? "Leave current call" : "Call diagnostics") {
            if draft { RecordingDraftPreview() }
            else if recording || discard { RecordingPreview(discard: discard) }
            else if gallery { GalleryPreview() }
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
        .defaultSize(width: recording || draft ? 640 : linking || clearing ? 680 : 520,
                     height: recording || draft ? 84 : discard ? 280 : linking || clearing ? 420 : 440)
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
    @State private var tab: MediaGalleryTab = .media
    @State private var order: MediaSortOrder = .date
    @Environment(\.dismiss) var dismiss
    var body: some View { GalleryPanel(tab: $tab, order: $order, onBack: { dismiss() }) }
}

struct GalleryPanel: View {
    @Binding var tab: MediaGalleryTab
    @Binding var order: MediaSortOrder
    var onBack: () -> Void

    var body: some View {
        ConversationPanel(onBack: onBack) {
            MediaGalleryPanelHeader(tab: $tab, sortOrder: $order)
        } content: {
            MediaGalleryEmptyState(tab: tab)
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
