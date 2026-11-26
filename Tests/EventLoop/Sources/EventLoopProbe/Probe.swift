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
        Text("First window").task {
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
@main private struct Probe: App {
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
        Window("Second", id: "second") { SecondWindow(count: $count) }
        WindowGroup(Text("Item"), id: "item", for: Int.self) { item in
            Text(item.wrappedValue.map(String.init) ?? "New").frame(width: 120, height: 80)
        }
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
