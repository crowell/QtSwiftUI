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
@main private struct Probe: App {
    @State private var model = Model()
    var body: some Scene {
        WindowGroup {
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
        .defaultSize(width: 260, height: 100)
    }
}
