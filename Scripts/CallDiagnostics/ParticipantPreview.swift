import SwiftUI

struct ParticipantPreview: View {
    let blocked = GroupCallRemoteParticipantInfo(demuxId: 11, conversation: JoinRequestPreview.participant,
                                                hasRemoteVideo: false, isBlocked: true)
    let speaker = GroupCallRemoteParticipantInfo(demuxId: 12, conversation: LobbyPreview.members[1],
                                                hasRemoteAudio: true, hasRemoteVideo: false, raisedHandOrder: 0)

    var body: some View {
        HStack(spacing: 12) {
            GroupCallRemoteParticipant(participant: blocked, width: 260, height: 180, inGrid: true)
            GroupCallRemoteParticipant(participant: speaker, width: 260, height: 180, inGrid: true, audioLevel: 0.6)
        }
        .padding(12)
        .background(Color.black)
        .environment(\.colorScheme, .dark)
        .environment(\.axoStaticRendering, true)
    }
}
