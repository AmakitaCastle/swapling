import CoreGraphics
import XCTest
@testable import IslandCore

/// Points sampled on a real 1470×956 notch screen during hover testing.
final class IslandOutlineTests: XCTestCase {
    // Collapsed with two pins: body x=571.5…898.5, y=0…32, shoulders 6, bottom radius 10.
    private let collapsed = CGRect(x: 571.5, y: 0, width: 327, height: 32)
    // Expanded: body x=500…970, y=0…540, shoulders 14, bottom radius 26.
    private let expanded = CGRect(x: 500, y: 0, width: 470, height: 540)

    private func onCollapsed(_ x: CGFloat, _ y: CGFloat) -> Bool {
        IslandOutline.contains(CGPoint(x: x, y: y), in: collapsed, topExtension: 6, bottomRadius: 10)
    }

    private func onExpanded(_ x: CGFloat, _ y: CGFloat) -> Bool {
        IslandOutline.contains(CGPoint(x: x, y: y), in: expanded, topExtension: 14, bottomRadius: 26)
    }

    func testCollapsedBottomCornersAreNotHot() {
        XCTAssertFalse(onCollapsed(897, 31)) // A10, right corner
        XCTAssertFalse(onCollapsed(573, 31)) // A09, left corner
    }

    func testCollapsedShouldersAreHot() {
        XCTAssertTrue(onCollapsed(570, 0.5)) // A11
        XCTAssertTrue(onCollapsed(900, 0.5)) // A12
        XCTAssertFalse(onCollapsed(568, 1))
        XCTAssertFalse(onCollapsed(902, 1))
    }

    func testCollapsedBodyAndOutside() {
        XCTAssertTrue(onCollapsed(735, 30))  // A02
        XCTAssertTrue(onCollapsed(890, 30))
        XCTAssertTrue(onCollapsed(573, 16))  // A04
        XCTAssertTrue(onCollapsed(897, 16))  // A06
        XCTAssertFalse(onCollapsed(735, 34)) // A01
        XCTAssertFalse(onCollapsed(570, 16)) // A03
        XCTAssertFalse(onCollapsed(900, 16)) // A05
    }

    func testExpandedCornersAreOutside() {
        XCTAssertFalse(onExpanded(501, 535)) // B04
        XCTAssertFalse(onExpanded(969, 535)) // B05
        XCTAssertTrue(onExpanded(735, 535))  // B03
        XCTAssertTrue(onExpanded(501, 200))  // B01
        XCTAssertTrue(onExpanded(969, 200))  // B02
        XCTAssertFalse(onExpanded(971, 200)) // B06
    }
}

/// Replays a recorded hover retest through the hover hit-test the view uses.
/// Collapsed body x=565.5…904.5, y=0…32 (two-letter badges); the hover view starts one shoulder
/// (6pt) left of the body, so local x = screen x − 559.5.
final class HoverRetestTests: XCTestCase {
    private let size = CGSize(width: 339, height: 32)

    private func hovered(_ x: CGFloat, _ y: CGFloat, size: CGSize? = nil) -> Bool {
        IslandOutline.hoverContains(
            CGPoint(x: x - 559.5, y: y), islandSize: size ?? self.size, topExtension: 6, bottomRadius: 10
        )
    }

    func testNormalEntriesExpand() {
        XCTAssertTrue(hovered(903, 24))  // right side into the outline
        XCTAssertTrue(hovered(735, 30))  // from below into the middle
        XCTAssertTrue(hovered(860, 16))  // right ear
        XCTAssertTrue(hovered(610, 16))  // left ear
        XCTAssertTrue(hovered(567, 16))  // from the left
        XCTAssertTrue(hovered(903, 16))  // from the right
        XCTAssertTrue(hovered(564, 0.5)) // left shoulder
        XCTAssertTrue(hovered(906, 0.5)) // right shoulder
    }

    func testTransparentCornersStayCollapsed() {
        XCTAssertFalse(hovered(903, 31))
        XCTAssertFalse(hovered(567, 31))
        XCTAssertFalse(hovered(903, 34))
        XCTAssertFalse(hovered(735, 34))
    }

    /// The shipped bug: the measured size stayed zero, so every point above missed.
    func testUnmeasuredIslandNeverHovers() {
        XCTAssertFalse(hovered(735, 16, size: .zero))
    }
}
