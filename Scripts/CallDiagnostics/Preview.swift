import SwiftUI

@main
struct DiagnosticPreview: App {
    var body: some Scene {
        let linkError = CommandLine.arguments.contains("--link-error")
        let linking = linkError || CommandLine.arguments.contains("--link-device")
        let leaveCall = CommandLine.arguments.contains("--leave-call")
        WindowGroup(linking ? "Link device" : leaveCall ? "Leave current call" : "Call diagnostics") {
            if linking { DeviceLinkPreview(showError: linkError) }
            else if leaveCall { LeaveCallPreview() }
            else { DiagnosticContent() }
        }
        .defaultSize(width: linking ? 680 : 520, height: linking ? 420 : 440)
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
