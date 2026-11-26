import SwiftUI
import SignalI18n

struct UsernameCardPreview: View {
    static let link = "https://signal.me/#eu/abcdefghijklmnop"
    static let username = "alice.42"
    @Environment(\.i18n) private var i18n

    var body: some View {
        UsernameLinkCard.Card(link: Self.link, usernameLines: UsernameLinkCard.split(Self.username, words: false,
                              maxWidth: UsernameLinkCard.usernameMaxWidth, style: UsernameLinkCard.usernameStyle),
                              hintLines: UsernameLinkCard.split(i18n("icu:UsernameLinkModalBody__hint"), words: true,
                              maxWidth: UsernameLinkCard.hintMaxWidth, style: UsernameLinkCard.hintStyle),
                              color: .blue, hintDirection: i18n.direction == .rightToLeft ? .rightToLeft : .leftToRight)
    }
}
