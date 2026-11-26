import SwiftUI

@MainActor @Observable
final class SettingsModel {
    var downloads = AutoDownloadAttachment()
    var quality: String? = "standard"
    var notify = true
    var ring = false
    var relay = false
    var camera: String? = SettingsModel.cameras[0].deviceId
    var microphone: AudioDevicePref = .nonWindowsDefault
    var speaker: AudioDevicePref = .specificDevice(SettingsModel.speakers.devices[1])
}

struct SettingsPreview: View {
    let calls: Bool
    @State var settings = SettingsModel()

    var body: some View {
        @Bindable var settings = settings
        Group {
            if calls {
                PreferencesCallsPage(hasIncomingCallNotifications: $settings.notify, hasCallRingtoneNotification: $settings.ring,
                    hasRelayCalls: $settings.relay, devices: CallingDeviceSelectionItems(
                        availableCameras: SettingsModel.cameras, availableMicrophones: SettingsModel.microphones,
                        availableSpeakers: SettingsModel.speakers, selectedCamera: settings.camera,
                        selectedMicrophone: settings.microphone, selectedSpeaker: settings.speaker,
                        onSelectedCameraChange: { settings.camera = $0 }, onSelectedMicrophoneChange: { settings.microphone = $0 },
                        onSelectedSpeakerChange: { settings.speaker = $0 }))
            } else {
                PreferencesDataUsagePage(autoDownload: $settings.downloads, sentMediaQuality: $settings.quality)
            }
        }.axoLayerHost()
    }
}

// Portable text drawing for AxoList headers that combine text and symbols.
struct AxoInlineFlowText: View {
    let pieces: [AxoInlinePiece]
    let style: CSSTextStyle
    let alignment: TextAlignment
    let maxLines: Int?
    let onAction: (Int) -> Void

    var body: some View {
        let runs = pieces.map { piece -> CSSTextRun in
            switch piece {
            case .text(let text): return CSSTextRun(text)
            case .styled(let text, let weight, let color):
                var run = CSSTextRun(text)
                run.fontName = AxoFonts.interName(weight: weight)
                run.color = color.map { AxoColor($0) }
                return run
            case .glyph(let glyph):
                var run = CSSTextRun(String(glyph))
                run.fontName = "Signal Symbols"
                return run
            case .action(let text, let id):
                let unbroken = text.replacingOccurrences(of: " ", with: "\u{00A0}")
                var run = CSSTextRun("\u{2068}\(unbroken)\u{2069}")
                run.action = String(id)
                return run
            }
        }
        CSSText(runs: runs, style: style, alignment: alignment) { if let id = Int($0) { onAction(id) } }
            .lineLimit(maxLines)
    }
}
