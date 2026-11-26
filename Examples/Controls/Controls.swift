import SwiftUI

struct Settings: View {
    @State private var displayName = "Alex"
    @State private var notifications = true
    @State private var volume = 0.65
    @State private var saved = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Preferences").font(.largeTitle.bold())
            Divider()
            Text("Display name").font(.headline)
            TextField("Display name", text: $displayName).accessibilityIdentifier("display-name")
            Toggle("Message notifications", isOn: $notifications).accessibilityIdentifier("notifications")
            if notifications {
                HStack {
                    Text("Alert volume")
                    Spacer()
                    Text("\(Int((volume * 100).rounded()))%").foregroundStyle(.secondary).accessibilityIdentifier("volume-label")
                }
                Slider(value: $volume, in: 0...1, step: 0.05)
            }
            Divider()
            HStack {
                Text(saved).font(.footnote).foregroundStyle(.secondary).accessibilityIdentifier("saved")
                Spacer()
                Button("Save") { saved = "Saved for \(displayName)" }.disabled(displayName.isEmpty).accessibilityIdentifier("save")
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.white)
    }
}
@main struct ControlsApp: App {
    var body: some Scene { WindowGroup("Preferences") { Settings() }.defaultSize(width: 460, height: 360) }
}
