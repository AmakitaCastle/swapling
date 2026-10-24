import XCTest
@testable import IslandCore

final class HoverIntentTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 0)
    private func t(_ s: Double) -> Date { t0.addingTimeInterval(s) }

    func testRestingOpensAfterTheDelay() {
        var intent = HoverIntent(delay: 0.4)
        XCTAssertEqual(intent.update(point: CGPoint(x: 100, y: 10), at: t(0)), t(0.4))
        XCTAssertFalse(intent.isReady(at: t(0.39)))
        XCTAssertTrue(intent.isReady(at: t(0.4)))
    }

    func testSmallJitterDoesNotRestartTheWait() {
        var intent = HoverIntent(delay: 0.4)
        intent.update(point: CGPoint(x: 100, y: 10), at: t(0))
        XCTAssertEqual(intent.update(point: CGPoint(x: 106, y: 13), at: t(0.2)), t(0.4))
        XCTAssertTrue(intent.isReady(at: t(0.4)))
    }

    func testSweepingAcrossNeverOpens() {
        // The pointer crosses a 300-point-wide island in 0.5 s, moving 30 points every 50 ms.
        var intent = HoverIntent(delay: 0.4)
        var x: CGFloat = 0
        for step in 0..<10 {
            intent.update(point: CGPoint(x: x, y: 12), at: t(Double(step) * 0.05))
            XCTAssertFalse(intent.isReady(at: t(Double(step) * 0.05)))
            x += 30
        }
        intent.update(point: nil, at: t(0.5))
        XCTAssertFalse(intent.isReady(at: t(2)))
    }

    func testLeavingCancelsAndComingBackStartsOver() {
        var intent = HoverIntent(delay: 0.4)
        intent.update(point: CGPoint(x: 50, y: 10), at: t(0))
        intent.update(point: nil, at: t(0.3))
        XCTAssertFalse(intent.isReady(at: t(0.5)))
        XCTAssertEqual(intent.update(point: CGPoint(x: 50, y: 10), at: t(1)), t(1.4))
    }

    func testDelayChoices() {
        XCTAssertEqual(HoverDelay.allCases.map(\.seconds), [0.2, 0.4, 0.7])
    }
}
