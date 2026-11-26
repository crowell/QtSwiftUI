import XCTest
#if os(Linux)
import QtBridge
@testable import SwiftUI
#else
import SwiftUI
#endif

final class TransactionTests: XCTestCase {
    func testBindingSetterReceivesTheBindingsTransaction() {
        var observed: [Animation?] = []
        struct Model { var count = 0 }
        var model = Model()
        let binding = Binding(get: { model }, set: { value, transaction in
            model = value
            observed.append(transaction.animation)
        })
        let linear = Animation.linear(duration: 2)
        withAnimation(linear) { binding.count.wrappedValue = 1 }
        var selected = Transaction(animation: .easeOut(duration: 3))
        selected.isContinuous = true
        let adapted = binding.transaction(selected)
        XCTAssertTrue(adapted.transaction.isContinuous)
        adapted.count.wrappedValue = 2
        withAnimation(nil) { binding.animation(linear).wrappedValue = Model(count: 3) }
        XCTAssertEqual(observed, [nil, selected.animation, linear])
        XCTAssertEqual(model.count, 3)
        XCTAssertNotEqual(Animation.default, Animation.interpolatingSpring(duration: 0.55))
    }

    func testRaisedHandSpringMatchesNativeDisplacement() {
        for (time, expected) in [(0.0, 0.0), (0.1, 0.5825511416790141), (0.25, 1.4908280513219978), (0.5, 0.7606473716164275)] {
            #if os(Linux)
            let value = Animation.spring(response: 0.5, dampingFraction: 0.22).fraction(at: time)
            #else
            let value = Spring(response: 0.5, dampingRatio: 0.22).value(target: 1.0, initialVelocity: 0.0, time: time)
            #endif
            XCTAssertEqual(value, expected, accuracy: 1e-8)
        }
        XCTAssertEqual(Animation.snappy, .spring(duration: 0.5, bounce: 0.15))
        XCTAssertEqual(Animation.interactiveSpring, .spring(duration: 0.15, bounce: 0.15, blendDuration: 0.25))
    }

    func testControlActiveStateAndAppearanceShareEnvironmentStorage() {
        var environment = EnvironmentValues()
        XCTAssertEqual(environment.controlActiveState, .key)
        environment.controlActiveState = .active
        XCTAssertTrue(environment.appearsActive)
        environment.appearsActive = false
        XCTAssertEqual(environment.controlActiveState, .inactive)
        environment.appearsActive = true
        XCTAssertEqual(environment.controlActiveState, .key)
    }

    func testSegmentedIndicatorSpringSamplesMatchTheSDK() {
        for (mass, stiffness, damping, speed, time, expected) in [
            (1.0, 422.0, 37.3, 0.3, 0.1, 0.648712950759878),
            (1, 422, 37.3, 0.3, 0.5, 1.000209750420062),
            (2, 50, 20, 0.3, 0.1, 0.10839993022242889),
            (2, 50, 30, 0.3, 0.1, 0.09378746605252455)
        ] {
            #if os(Linux)
            let value = Animation.interpolatingSpring(mass: mass, stiffness: stiffness, damping: damping,
                                                      initialVelocity: speed).fraction(at: time)
            #else
            let value = Spring(mass: mass, stiffness: stiffness, damping: damping, allowOverDamping: true)
                .value(target: 1.0, initialVelocity: speed, time: time)
            #endif
            XCTAssertEqual(value, expected, accuracy: 1e-8)
        }
    }

    #if os(Linux)
    @MainActor func testAnimatedStateMutationReachesQtThroughABinding() async {
        struct Fade: View {
            @State var active = false
            var body: some View {
                VStack(spacing: 0) {
                    Button("Fade") { withAnimation(.linear(duration: 1)) { $active.wrappedValue.toggle() } }
                        .frame(height: 25).accessibilityIdentifier("fade")
                    Rectangle().fill(.black).opacity(active ? 1 : 0).background(Color.white)
                }
            }
        }
        var now = 0.0
        let host = Host(title: "Transaction", animationClock: { now }) { Fade().resolve($0) }
        host.open(width: 80, height: 80)
        defer { host.close() }
        XCTAssertEqual(qs_click(host.window, "fade"), 1)
        func value(_ time: Double) -> Int {
            now = time
            host.update()
            qs_flush()
            return Int(qs_pixel(host.window, 40, 50) & 255)
        }
        XCTAssertEqual(value(0), 255)
        XCTAssertEqual(Double(value(0.5)), 128, accuracy: 1)
        XCTAssertEqual(value(1), 0)
    }
    #endif
}
