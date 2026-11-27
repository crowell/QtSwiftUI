import SwiftUI
import XCTest

final class AccessibilityTraitsTests: XCTestCase {
    func testCompositeMembersMatchTheDesktopSDK() {
        let checked: AccessibilityTraits = [.isToggle, .isSelected]
        var traits = AccessibilityTraits.isToggle
        XCTAssertTrue(traits.contains([]))
        XCTAssertFalse(traits.contains(checked))
        let inserted = traits.insert(.isSelected)
        XCTAssertTrue(inserted.inserted)
        XCTAssertEqual(inserted.memberAfterInsert, checked)
        let duplicate = traits.insert(.isToggle)
        XCTAssertFalse(duplicate.inserted)
        XCTAssertEqual(duplicate.memberAfterInsert, checked)
        XCTAssertEqual(traits.remove(.isHeader), checked)
        XCTAssertEqual(traits.remove(.isSelected), .isToggle)
        XCTAssertEqual(traits.update(with: checked), .isToggle)
        XCTAssertNil(traits.update(with: .isSelected))
        XCTAssertTrue(traits.isEmpty)
        XCTAssertEqual(traits.remove([]), AccessibilityTraits())
    }

    func testTabBarAndStaticTextRemainIndependent() {
        let both: AccessibilityTraits = [.isTabBar, .isStaticText]
        var traits = both.union(.isHeader)
        XCTAssertEqual(traits.intersection(both), both)
        traits.formSymmetricDifference(.isStaticText)
        XCTAssertEqual(traits, [.isTabBar, .isHeader])
        XCTAssertEqual(traits.subtracting(.isTabBar), .isHeader)
        traits.formIntersection(both)
        XCTAssertEqual(traits, .isTabBar)
    }
}
