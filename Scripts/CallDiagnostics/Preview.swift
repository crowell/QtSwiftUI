import SwiftUI

@main
struct DiagnosticPreview: App {
    var body: some Scene {
        WindowGroup("Call diagnostics") { DiagnosticContent() }
            .defaultSize(width: 520, height: 440)
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
