import SwiftUI

struct MuteUntilPreview: View {
    static let now = Date(timeIntervalSince1970: 1_793_793_600)
    static let zone = TimeZone(identifier: "Europe/Lisbon")!
    var submit: ((Date) -> Void)?
    var close: (() -> Void)?
    @Environment(\.dismiss) var dismiss

    var body: some View {
        AxoBaseDialog.Host {
            MuteUntilDialog(now: Self.now, onSubmit: { date in
                if let submit { submit(date) } else { dismiss() }
            }, onClose: { if let close { close() } else { dismiss() } })
        }
        .background(AxoColor.surfacePrimary)
        .environment(\.timeZone, Self.zone)
    }
}
