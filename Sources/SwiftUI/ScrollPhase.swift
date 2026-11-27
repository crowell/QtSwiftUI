import QtBridge

@frozen public enum ScrollPhase: Hashable, Sendable, CustomDebugStringConvertible {
    case idle, tracking, interacting, decelerating, animating
    public var isScrolling: Bool { self != .idle }
    public var debugDescription: String {
        switch self {
        case .idle: "idle"
        case .tracking: "tracking"
        case .interacting: "interacting"
        case .decelerating: "decelerating"
        case .animating: "animating"
        }
    }

    fileprivate init(native: QSScrollPhase) {
        switch native {
        case QSScrollTracking: self = .tracking
        case QSScrollInteracting: self = .interacting
        case QSScrollDecelerating: self = .decelerating
        case QSScrollAnimating: self = .animating
        default: self = .idle
        }
    }
}

public struct ScrollPhaseChangeContext {
    public private(set) var geometry: ScrollGeometry
    public private(set) var velocity: CGVector?
}

struct ScrollPhaseReport: Equatable {
    struct Change: Equatable {
        let before, after: ScrollPhase
        let geometry: ScrollGeometry
        let velocity: CGVector
    }
    let source: UInt
    let phase: ScrollPhase
    let geometry: ScrollGeometry
    let changes: [Change]

    init(widget: UnsafeMutableRawPointer, geometry: ScrollGeometry, shift: CGPoint) {
        source = UInt(bitPattern: widget)
        self.geometry = geometry
        phase = ScrollPhase(native: qs_scroll_phase(widget))
        var event = QSScrollPhaseEvent()
        var changes: [Change] = []
        while qs_scroll_next_phase(widget, &event) != 0 {
            var atTransition = geometry
            atTransition.contentOffset = CGPoint(x: event.x - shift.x, y: event.y - shift.y)
            changes.append(Change(before: ScrollPhase(native: event.before), after: ScrollPhase(native: event.after),
                                  geometry: atTransition, velocity: CGVector(dx: event.dx, dy: event.dy)))
        }
        self.changes = changes
    }
}

enum FirstScrollPhase: PreferenceKey {
    static let defaultValue: ScrollPhaseReport? = nil
    static func reduce(value: inout ScrollPhaseReport?, nextValue: () -> ScrollPhaseReport?) {
        if value == nil { value = nextValue() }
    }
}

extension View {
    nonisolated public func onScrollPhaseChange(_ action: @escaping (_ oldPhase: ScrollPhase, _ newPhase: ScrollPhase) -> Void) -> some View {
        onScrollPhaseChange { before, after, _ in action(before, after) }
    }

    nonisolated public func onScrollPhaseChange(_ action: @escaping (_ oldPhase: ScrollPhase, _ newPhase: ScrollPhase, _ context: ScrollPhaseChangeContext) -> Void) -> some View {
        observePreference(FirstScrollPhase.self, project: { $0 }) { old, next in
            guard let next else { return }
            if old.flatMap({ $0 })?.source != next.source {
                let initial = next.changes.first?.before ?? next.phase
                action(initial, initial, .init(geometry: next.changes.first?.geometry ?? next.geometry, velocity: .zero))
            }
            for change in next.changes {
                action(change.before, change.after, .init(geometry: change.geometry, velocity: change.velocity))
            }
        }
    }
}
