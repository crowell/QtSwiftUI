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
@main private struct Probe: App {
    @State private var model = Model()
    var body: some Scene {
        WindowGroup {
            GeometryReader { proxy in
                Status().onAppear { print("Appeared at \(Int(proxy.size.width)) x \(Int(proxy.size.height))") }
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
