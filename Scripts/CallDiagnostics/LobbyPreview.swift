import SwiftUI

extension CSSTextLayout {
    // The join button measures unwrapped localized variants before choosing its width.
    static func make(_ text: String, _ style: CSSTextStyle, wrap: CSSTextWrap, maxWidth: CGFloat?) -> CGSize {
        precondition(wrap == .nowrap && maxWidth == nil)
        return CGSize(width: AxoFonts.width(text, style: style), height: style.lineHeight)
    }
}

// The fixture supplies camera pixels at the capture boundary. The lobby's
// camera-off path needs no camera or account in the Ubuntu container.
public struct LocalVideoModel {
    let frame: RGBAImage
}
struct LocalVideoView: View {
    let model: LocalVideoModel
    let fit: ObjectFit
    var body: some View { PixelImage(model.frame, fit: fit).scaleEffect(x: -1, y: 1) }
}

@MainActor @Observable final class LobbyPreviewModel {
    var audio = true
    var ring = true
    var connecting = false
    var cancelled = false
    var settings = false
}

struct LobbyPreview: View {
    @State var model = LobbyPreviewModel()
    static let crew = CallingConversation(id: "crew", title: "Ferry crew", color: "A180", conversationType: .group)
    static let me = CallingConversation(id: "me", title: "You", isMe: true)
    static let members = [me, CallingConversation(id: "neve", title: "Neve", color: "A160"),
                          CallingConversation(id: "max", title: "Max", color: "A190")]

    var body: some View {
        if model.cancelled {
            CallsTabPreview()
        } else if model.settings {
            SettingsPreview(calls: true)
        } else {
            CallingLobby(callMode: .group, conversation: Self.crew, me: Self.me, groupMembers: Self.members,
                         hasLocalAudio: model.audio, hasLocalVideo: false, hasCamera: false,
                         isCallConnecting: model.connecting, outgoingRing: model.ring,
                         setLocalAudio: { model.audio = $0 }, setOutgoingRing: { model.ring = $0 },
                         onJoinCall: { model.connecting = true }, onCallCanceled: { model.cancelled = true },
                         toggleSettings: { model.settings = $0 })
        }
    }
}
