import Combine
import Foundation
import XCTest
#if os(Linux)
import QtBridge
@testable import SwiftUI
#else
import AppKit
import SwiftUI
#endif

private final class CountingPublisher: Publisher {
    typealias Output = Int
    typealias Failure = Never
    let subject = PassthroughSubject<Int, Never>()
    private(set) var starts = 0, stops = 0

    func receive<S: Subscriber>(subscriber: S) where S.Input == Int, S.Failure == Never {
        starts += 1
        subject.handleEvents(receiveCancel: { [weak self] in self?.stops += 1 }).receive(subscriber: subscriber)
    }
}

private struct Feed: Combine.Publisher {
    let source: CountingPublisher
    let key: Int
    func receive<S: Subscriber>(subscriber: S) where S.Input == Int, S.Failure == Never {
        source.receive(subscriber: subscriber)
    }
    typealias Output = Int
    typealias Failure = Never
}

@MainActor @Observable private final class SubscriptionModel {
    let first = CountingPublisher(), second = CountingPublisher()
    let center = NotificationCenter()
    let notification = Notification.Name("SubscriptionTest")
    var visible = true
    var useSecond = false
    var key = 0
    var generation = 0
    @ObservationIgnored var events: [String] = []
}

private struct SubscriptionFixture: View {
    let model: SubscriptionModel

    var body: some View {
        let generation = model.generation
        if model.visible {
            SubscriptionView(content: Text("Feed"), publisher: Feed(source: model.useSecond ? model.second : model.first, key: model.key)) {
                model.events.append("value \($0) \(generation)")
            }
            .onReceive(model.center.publisher(for: model.notification)) { notification in
                MainActor.preconditionIsolated()
                model.events.append("notification \(notification.object as? String ?? "")")
            }
            .onAppear { model.events.append("appear") }
            .onDisappear { model.events.append("disappear") }
        }
    }
}

final class SubscriptionTests: XCTestCase {
    @MainActor func testSubscriptionFollowsTheViewAndUpdatesItsAction() async throws {
        let model = SubscriptionModel()
        let content = SubscriptionFixture(model: model)
        #if os(Linux)
        let host = Host(title: "Feed") { content.resolve($0) }
        host.open(width: 120, height: 80)
        defer { host.close() }
        #else
        let hosting = NSHostingView(rootView: content)
        let window = NSWindow(contentRect: CGRect(x: 80, y: 80, width: 120, height: 80),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = hosting
        window.orderFrontRegardless()
        defer { window.orderOut(nil) }
        #endif
        func settle() async throws {
            for _ in 0..<6 {
                try await Task.sleep(for: .milliseconds(10))
                #if os(Linux)
                qs_flush()
                #else
                hosting.layoutSubtreeIfNeeded()
                #endif
            }
        }

        try await settle()
        XCTAssertEqual(model.events, ["appear"])
        model.first.subject.send(1)
        XCTAssertEqual(model.events.last, "value 1 0")
        model.generation = 1
        try await settle()
        model.first.subject.send(2)
        XCTAssertEqual(model.events.last, "value 2 1")
        XCTAssertEqual(model.first.starts, 1)

        model.key = 1
        try await settle()
        XCTAssertEqual(model.first.stops, 1)
        XCTAssertEqual(model.first.starts, 2)
        model.useSecond = true
        try await settle()
        model.first.subject.send(3)
        XCTAssertEqual(model.events.last, "value 2 1")
        XCTAssertEqual(model.first.stops, 2)
        model.second.subject.send(4)
        XCTAssertEqual(model.events.last, "value 4 1")

        let center = model.center, name = model.notification
        await Task.detached {
            center.post(name: name, object: "one")
            center.post(name: name, object: "two")
        }.value
        try await settle()
        XCTAssertEqual(model.events.suffix(2), ["notification one", "notification two"])

        model.visible = false
        try await settle()
        XCTAssertEqual(model.second.stops, 1)
        model.second.subject.send(5)
        center.post(name: name, object: "hidden")
        XCTAssertEqual(model.events.last, "disappear")
        model.visible = true
        try await settle()
        XCTAssertEqual(model.second.starts, 2)
        center.post(name: name, object: "visible")
        XCTAssertEqual(model.events.last, "notification visible")
        model.second.subject.send(completion: .finished)
        model.generation += 1
        try await settle()
        XCTAssertGreaterThan(model.second.starts, 2)
    }

    @MainActor func testImmediatePublisherRunsBeforeAppearance() {
        let _: Never.Type = SubscriptionView<Just<Int>, Text>.Body.self
        var seen: [String] = []
        let view = Text("Label").onReceive(Just(7)) { seen.append(String($0)) }
            .onAppear { seen.append("appear") }
        XCTAssertNotNil(ImageRenderer(content: view).cgImage)
        XCTAssertEqual(seen, ["7", "appear"])
    }
}
