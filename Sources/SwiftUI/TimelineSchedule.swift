public protocol TimelineSchedule {
    typealias Mode = TimelineScheduleMode
    associatedtype Entries: Sequence where Entries.Element == Date
    func entries(from startDate: Date, mode: Mode) -> Entries
}

public enum TimelineScheduleMode: Hashable, Sendable { case normal, lowFrequency }

private struct DateStep: Sendable {
    var date: Date?
    let interval: TimeInterval
    mutating func next() -> Date? {
        defer { date = date?.addingTimeInterval(interval) }
        return date
    }
}

public struct PeriodicTimelineSchedule: TimelineSchedule, Sendable {
    private let origin: Date
    private let interval: TimeInterval
    public init(from startDate: Date, by interval: TimeInterval) {
        origin = startDate
        self.interval = interval
    }
    public struct Entries: Sequence, IteratorProtocol, Sendable {
        fileprivate var step: DateStep
        public mutating func next() -> Date? { step.next() }
    }
    public func entries(from startDate: Date, mode: Mode) -> Entries {
        let index = (startDate.timeIntervalSince(origin) / interval).rounded(.towardZero)
        return Entries(step: DateStep(date: origin.addingTimeInterval(index * interval), interval: interval))
    }
}

public struct EveryMinuteTimelineSchedule: TimelineSchedule, Sendable {
    public init() {}
    public struct Entries: Sequence, IteratorProtocol, Sendable {
        fileprivate var step: DateStep
        public mutating func next() -> Date? { step.next() }
    }
    public func entries(from startDate: Date, mode: Mode) -> Entries {
        let start = (startDate.timeIntervalSinceReferenceDate / 60).rounded(.down) * 60
        return Entries(step: DateStep(date: Date(timeIntervalSinceReferenceDate: start), interval: 60))
    }
}

public struct ExplicitTimelineSchedule<Entries: Sequence>: TimelineSchedule where Entries.Element == Date {
    private let dates: Entries
    public init(_ dates: Entries) { self.dates = dates }
    public func entries(from startDate: Date, mode: Mode) -> Entries { dates }
}

public struct AnimationTimelineSchedule: TimelineSchedule, Sendable {
    private let interval: Double
    private let paused: Bool
    public init(minimumInterval: Double? = nil, paused: Bool = false) {
        interval = minimumInterval ?? (1.0 / 120)
        self.paused = paused
    }
    public struct Entries: Sequence, IteratorProtocol, Sendable {
        fileprivate var step: DateStep
        public mutating func next() -> Date? { step.next() }
    }
    public func entries(from start: Date, mode: Mode) -> Entries {
        Entries(step: DateStep(date: paused || mode == .lowFrequency ? nil : start, interval: interval))
    }
}
extension TimelineSchedule where Self == PeriodicTimelineSchedule {
    public static func periodic(from startDate: Date, by interval: TimeInterval) -> Self { .init(from: startDate, by: interval) }
}
extension TimelineSchedule where Self == EveryMinuteTimelineSchedule {
    public static var everyMinute: Self { Self() }
}
extension TimelineSchedule where Self == AnimationTimelineSchedule {
    public static var animation: Self { Self() }
    public static func animation(minimumInterval: Double? = nil, paused: Bool = false) -> Self {
        .init(minimumInterval: minimumInterval, paused: paused)
    }
}
extension TimelineSchedule {
    public static func explicit<S: Sequence>(_ dates: S) -> Self where Self == ExplicitTimelineSchedule<S>, S.Element == Date {
        .init(dates)
    }
}
