import XCTest
@testable import IslandCore

final class AlertGroupTests: XCTestCase {
    private func window(_ id: String, used: Double, minutes: Int) -> QuotaWindow {
        QuotaWindow(id: id, title: id, usedPercent: used, windowMinutes: minutes)
    }

    func testSameProviderEventsShareOnePopup() {
        let events: [IslandEvent] = [
            .threshold(providerID: "claude", window: window("primary", used: 87, minutes: 300), level: 80),
            .threshold(providerID: "codex", window: window("primary", used: 81, minutes: 300), level: 80),
            .threshold(providerID: "claude", window: window("secondary", used: 82, minutes: 10080), level: 80),
        ]
        let groups = AlertGroup.group(events)
        XCTAssertEqual(groups.map(\.providerID), ["claude", "codex"])
        XCTAssertEqual(groups[0].events.count, 2)
        XCTAssertEqual(groups[0].summary, "5h 已用 87% · 周 已用 82%")
    }

    func testPrimaryIsMostSevere() {
        let group = AlertGroup(providerID: "claude", events: [
            .reset(providerID: "claude", window: window("secondary", used: 2, minutes: 10080)),
            .exhausted(providerID: "claude", window: window("primary", used: 100, minutes: 300)),
            .threshold(providerID: "claude", window: window("tertiary", used: 96, minutes: 1440), level: 95),
        ])
        guard case .exhausted = group.primary else { return XCTFail("expected exhausted") }
    }

    func testQueuedPopupMergesNewerEvents() {
        var queue: [AlertGroup] = []
        AlertGroup.enqueue([.threshold(providerID: "claude", window: window("primary", used: 81, minutes: 300), level: 80)], into: &queue)
        AlertGroup.enqueue([.threshold(providerID: "claude", window: window("primary", used: 96, minutes: 300), level: 95)], into: &queue)
        XCTAssertEqual(queue.count, 1)
        XCTAssertEqual(queue[0].events.count, 1)
        guard case let .threshold(_, _, level) = queue[0].events[0] else { return XCTFail() }
        XCTAssertEqual(level, 95)
    }
}

extension AlertGroupTests {
    func testSubtitleUsesActualUsage() {
        let group = AlertGroup(providerID: "claude", events: [
            .threshold(providerID: "claude", window: window("primary", used: 87, minutes: 300), level: 80),
        ])
        XCTAssertEqual(group.subtitle(now: Date()), "已用 87%，剩余 13%")
        XCTAssertEqual(group.title, "Claude · primary")
    }
}
