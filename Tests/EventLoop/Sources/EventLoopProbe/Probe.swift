import SwiftUI

@Observable private final class Model {
    var message = "Waiting"
}
private struct Status: View {
    @Environment(Model.self) var model
    var body: some View {
        @Bindable var edit = model
        VStack {
            TextField("Message", text: $edit.message)
            Text(model.message)
        }
        .onChange(of: model.message) { previous, current in
            print("Observed \(previous) -> \(current)")
        }
    }
}
private struct TimedStatus: View {
    @State private var start: Date?
    var body: some View {
        Group {
            if let start {
                let finish = start.addingTimeInterval(0.18)
                TimelineView(.explicit([start, finish])) { tick in
                    Color.clear.onChange(of: tick.date) { _, newDate in
                        if newDate == finish { print("Timeline reached its scheduled date") }
                    }
                }
            } else {
                Color.clear.onAppear { start = Date() }
            }
        }.frame(height: 1)
    }
}
private struct FirstWindow: View {
    @Environment(\.openWindow) private var open
    @Binding var count: Int

    var body: some View {
        Picker("Window value", selection: $count) {
            ForEach(0..<3) { value in Text(String(value)) }
        }
        .pickerStyle(.segmented)
        .task {
            count = 1
            open(id: "second")
            open(id: "second")
        }
    }
}
private struct SecondWindow: View {
    @Environment(\.dismissWindow) private var dismiss
    @Binding var count: Int

    var body: some View {
        Text("Count \(count)")
            .task {
                print("Second window opened with \(count)")
                dismiss(id: "first")
                try? await Task.sleep(for: .milliseconds(80))
                count += 1
            }
            .onChange(of: count) { _, new in
                if new == 2 {
                    print("Second window observed shared state after first closed")
                    dismiss()
                }
            }
    }
}
private struct PreferencesWindow: View {
    @Environment(\.dismissWindow) var dismiss
    var body: some View {
        Text("Preferences")
            .task {
                print("Opened settings from a presented scene")
                dismiss(id: "welcome")
                dismiss()
            }
    }
}
private struct Welcome: View {
    @Environment(\.openSettings) var openSettings
    var body: some View {
        SettingsLink { Text("Open settings") }.task { openSettings() }
    }
}
private struct PreferencesProbe: App {
    var body: some Scene {
        WindowGroup { Text("Suppressed").onAppear { print("Unexpected initial window") } }
            .defaultLaunchBehavior(.suppressed)
        Window("Welcome", id: "welcome") { Welcome() }
            .defaultLaunchBehavior(.presented)
        Settings { PreferencesWindow() }
    }
}

private struct SavedPreference: View {
    @AppStorage("launch-count") var count = 0
    @Environment(\.dismissWindow) var dismiss
    var body: some View {
        Text("Count \(count)").task {
            let previous = count
            count += 1
            print("Stored count \(previous) -> \(count)")
            dismiss()
        }
    }
}
private struct StorageProbe: App {
    var body: some Scene {
        Window("Preferences", id: "stored") { SavedPreference() }
            .defaultAppStorage(UserDefaults(suiteName: "org.qtswiftui.event-loop-test")!)
    }
}

@main private enum Driver {
    @MainActor static func main() {
        if CommandLine.arguments.contains("--settings") { PreferencesProbe.main() }
        else if CommandLine.arguments.contains("--stored") { StorageProbe.main() }
        else { Probe.main() }
    }
}
private struct Probe: App {
    @State private var count = 0
    @State private var model = Model()
    var body: some Scene {
        WindowGroup(id: "first") {
            if CommandLine.arguments.contains("--windows") {
                FirstWindow(count: $count)
            } else {
                status
            }
        }
        .defaultSize(width: 260, height: 100)
        .defaultLaunchBehavior(.automatic)
        Window("Second", id: "second") { SecondWindow(count: $count) }
        WindowGroup(Text("Item"), id: "item", for: Int.self) { item in
            Text(item.wrappedValue.map(String.init) ?? "New").frame(width: 120, height: 80)
        }
        .defaultLaunchBehavior(.suppressed)
        .windowResizability(.contentSize)
        .defaultSize(CGSize(width: 120, height: 80))
        WindowGroup("Draft", for: String.self) { title in TextField("Title", text: title) }
            defaultValue: { "New draft" }
    }

    private var status: some View {
        GeometryReader { proxy in
            VStack(spacing: 0) {
                Status().onAppear { print("Appeared at \(Int(proxy.size.width)) x \(Int(proxy.size.height))") }
                TimedStatus()
            }
        }
        .environment(model)
        .task {
            try? await Task.sleep(for: .milliseconds(30))
            model.message = "Ready"
        }
    }
}
