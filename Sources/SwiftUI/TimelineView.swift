@MainActor private final class TimelineClock {
    var anchor = Date()
    var display: Date?
    private var wake: Date?
    private var timer: Task<Void, Never>?

    func schedule(_ next: Date?, host: Host) {
        guard wake != next else { return }
        cancel()
        guard let next else { return }
        wake = next
        timer = Task { [weak self, weak host] in
            do { try await Task.sleep(for: .seconds(max(0, next.timeIntervalSinceNow))) }
            catch { return }
            guard let self, let host, !Task.isCancelled else { return }
            self.wake = nil
            self.anchor = max(next, Date())
            host.update()
        }
    }
    func cancel() {
        timer?.cancel()
        timer = nil
        wake = nil
    }
}

public struct TimelineView<Schedule: TimelineSchedule, Content> {
    public struct Context {
        public enum Cadence: Comparable, Sendable { case live, seconds, minutes }
        public let date: Date
        public let cadence: Cadence
    }
    fileprivate let schedule: Schedule
    fileprivate let content: (Context) -> Content
}

public typealias TimelineViewDefaultContext = TimelineView<EveryMinuteTimelineSchedule, Never>.Context

extension TimelineView: View, Primitive where Content: View {
    public init(_ schedule: Schedule, @ViewBuilder content: @escaping (TimelineViewDefaultContext) -> Content) {
        self.schedule = schedule
        self.content = { content(TimelineViewDefaultContext(date: $0.date, cadence: .live)) }
    }
    @_disfavoredOverload
    public init(_ schedule: Schedule, @ViewBuilder content: @escaping (Context) -> Content) {
        self.schedule = schedule
        self.content = content
    }
    func elements(in context: SwiftUI.Context) -> [Element] {
        let clock = context.host.storage[context.path] as? TimelineClock ?? TimelineClock()
        context.host.storage[context.path] = clock
        context.host.liveStorage.insert(context.path)
        let now = Date()
        var entries = schedule.entries(from: clock.anchor, mode: .normal).makeIterator()
        var previous: Date?
        var next: Date?
        while let entry = entries.next(), entry.timeIntervalSinceReferenceDate.isFinite {
            // A non-advancing custom schedule has no future tick.
            if let previous, entry <= previous { break }
            if entry > now { next = entry; break }
            previous = entry
        }
        clock.display = previous ?? clock.display ?? now
        clock.schedule(next, host: context.host)
        context.host.lifetime(at: context.path, appear: {}, disappear: { clock.cancel() })
        return content(Context(date: clock.display ?? now, cadence: .live)).resolve(context.descending(.position(0)))
    }
}
