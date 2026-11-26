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
        let arabic = CommandLine.arguments.contains("--arabic")
        WindowGroup(gallery ? "All media" : clearing ? "Clearing data" : linking ? "Link device" : leaveCall ? "Leave current call" : "Call diagnostics") {
            if gallery { GalleryPreview() }
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
        .defaultSize(width: linking || clearing ? 680 : 520, height: linking || clearing ? 420 : 440)
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
