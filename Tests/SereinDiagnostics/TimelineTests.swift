import SwiftUI
import XCTest

final class TimelineTests: XCTestCase {
    func testBuiltInScheduleEntries() {
        let origin = Date(timeIntervalSinceReferenceDate: 10)
        let earlier = Date(timeIntervalSinceReferenceDate: 3)
        let later = Date(timeIntervalSinceReferenceDate: 32)
        let periodic = PeriodicTimelineSchedule(from: origin, by: 6)
        func dates<S: TimelineSchedule>(_ schedule: S, _ start: Date, _ mode: TimelineScheduleMode) -> [Double] {
            schedule.entries(from: start, mode: mode).prefix(3).map { $0.timeIntervalSinceReferenceDate }
        }
        XCTAssertEqual(dates(periodic, earlier, .normal), [4, 10, 16])
        XCTAssertEqual(dates(periodic, later, .lowFrequency), [28, 34, 40])
        XCTAssertEqual(dates(.everyMinute, later, .normal), [0, 60, 120])
        XCTAssertEqual(dates(.explicit([earlier, origin, later]), later, .normal), [3, 10, 32])
        XCTAssertEqual(dates(.animation(minimumInterval: 0.25), origin, .normal), [10, 10.25, 10.5])
        XCTAssertTrue(dates(.animation, earlier, .lowFrequency).isEmpty)
        XCTAssertTrue(dates(.animation(paused: true), earlier, .normal).isEmpty)
    }
}
