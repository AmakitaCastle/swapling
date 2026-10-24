import XCTest
@testable import IslandCore

final class CharacterLibraryTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testMoodFollowsStatus() {
        XCTAssertEqual(CharacterMood(status: .normal), .normal)
        XCTAssertEqual(CharacterMood(status: .balance), .normal)
        XCTAssertEqual(CharacterMood(status: .unconfirmed), .normal)
        XCTAssertEqual(CharacterMood(status: .nearLimit), .worried)
        XCTAssertEqual(CharacterMood(status: .limited(partial: true)), .exhausted)
        XCTAssertEqual(CharacterMood(status: .limited(partial: false)), .exhausted)
    }

    func testBundledArtworkFollowsQuotaAndRecovery() throws {
        // The repository ships no character art, so this lays out a bundled set to check the mapping.
        let bundled = root.appendingPathComponent("bundled", isDirectory: true)
        let folder = bundled.appendingPathComponent("codex", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for (index, mood) in [CharacterMood.normal, .worried, .exhausted].enumerated() {
            try Data([UInt8(index)]).write(to: folder.appendingPathComponent("\(mood.rawValue).png"))
        }
        let library = CharacterLibrary(root: root, bundledRoot: bundled)
        let now = Date(timeIntervalSince1970: 1_000_000)
        for (used, expected) in [(79.0, CharacterMood.normal), (80.0, .worried), (100.0, .exhausted), (25.0, .normal)] {
            let provider = ProviderUsage(id: "codex:work", windows: [
                QuotaWindow(id: "primary", title: "Session", usedPercent: used,
                            resetsAt: now.addingTimeInterval(3600))
            ], fetchedAt: now)
            let choice = try XCTUnwrap(MascotPicker.pick([provider], thresholds: .standard, now: now) {
                QuotaOverview.status(of: $0, thresholds: .standard, refreshInterval: 120, now: now)
            })
            XCTAssertEqual(choice.mood, expected)
            XCTAssertEqual(library.imageURL(for: choice.providerID, mood: choice.mood),
                           folder.appendingPathComponent("\(expected.rawValue).png"))
        }
    }

    func testFallsBackToNormalThenNothing() {
        let library = CharacterLibrary(root: root)
        let normal = library.folder(for: "claude").appendingPathComponent("normal.png")
        XCTAssertNil(library.imageURL(for: "claude", mood: .worried, fileExists: { _ in false }))
        XCTAssertEqual(library.imageURL(for: "claude", mood: .worried, fileExists: { $0 == normal }), normal)
        XCTAssertEqual(library.imageURL(for: "claude", mood: .exhausted, fileExists: { $0 == normal }), normal)
    }

    func testProviderIDCannotEscapeRoot() {
        let library = CharacterLibrary(root: root)
        XCTAssertEqual(library.folder(for: "../../etc").lastPathComponent, "etc")
        XCTAssertEqual(library.folder(for: "..").lastPathComponent, "_")
    }

    func testAccountInheritsBundledBaseProviderButOwnNormalOverrideWins() {
        let bundled = root.appendingPathComponent("bundled", isDirectory: true)
        let library = CharacterLibrary(root: root, bundledRoot: bundled)
        let bundledWorried = bundled.appendingPathComponent("claude/worried.png")
        let customNormal = library.folder(for: "claude:work").appendingPathComponent("normal.png")
        XCTAssertEqual(library.imageURL(for: "claude:work", mood: .worried,
                                       fileExists: { $0 == bundledWorried }), bundledWorried)
        XCTAssertEqual(library.imageURL(for: "claude:work", mood: .worried,
                                       fileExists: { $0 == bundledWorried || $0 == customNormal }), customNormal)
    }

    func testRemovingUserOverrideDoesNotDeleteBundledArtwork() throws {
        let bundled = root.appendingPathComponent("bundled", isDirectory: true)
        let library = CharacterLibrary(root: root, bundledRoot: bundled)
        let folder = bundled.appendingPathComponent("claude", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let normal = folder.appendingPathComponent("normal.png")
        try Data([1]).write(to: normal)
        try library.removeImage(providerID: "claude", mood: .normal)
        XCTAssertEqual(library.imageURL(for: "claude", mood: .worried), normal)
        XCTAssertTrue(FileManager.default.fileExists(atPath: normal.path))
    }

    func testZeroBalanceExhaustsOnlyWhenDataIsConfirmed() {
        let p = ProviderUsage(id: "openrouter", balance: Balance(amount: 0, currencyCode: "USD"))
        XCTAssertEqual(CharacterMood(provider: p, status: .balance), .exhausted)
        XCTAssertEqual(CharacterMood(provider: p, status: .unconfirmed), .normal)
        let positive = ProviderUsage(id: "openrouter", balance: Balance(amount: 0.01, currencyCode: "USD"))
        XCTAssertEqual(CharacterMood(provider: positive, status: .balance), .normal)
    }

    func testExpressionFollowsCustomizedQuotaThresholdAndIgnoresOldNumbers() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let p = ProviderUsage(id: "claude", windows: [QuotaWindow(id: "primary", title: "Session", usedPercent: 65)],
                              fetchedAt: now)
        func mood(_ provider: ProviderUsage, _ thresholds: QuotaThresholds) -> CharacterMood {
            let status = QuotaOverview.status(of: provider, thresholds: thresholds, refreshInterval: 120, now: now)
            return CharacterMood(provider: provider, status: status)
        }
        XCTAssertEqual(mood(p, .standard), .normal)
        XCTAssertEqual(mood(p, QuotaThresholds(warn1: 60, warn2: 90)), .worried)
        var old = p
        old.fetchedAt = now.addingTimeInterval(-3600)
        old.windows = [QuotaWindow(id: "primary", title: "Session", usedPercent: 100)]
        XCTAssertEqual(mood(old, .standard), .normal)
    }

    func testImportReplacesEarlierImageOfAnotherFormat() throws {
        let library = CharacterLibrary(root: root)
        let source = root.appendingPathComponent("src", isDirectory: true)
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let png = source.appendingPathComponent("a.png")
        let jpg = source.appendingPathComponent("b.JPG")
        try Data([1]).write(to: png)
        try Data([2]).write(to: jpg)

        try library.importImage(from: png, providerID: "codex", mood: .worried)
        let stored = try library.importImage(from: jpg, providerID: "codex", mood: .worried)

        XCTAssertEqual(stored.lastPathComponent, "worried.jpg")
        XCTAssertEqual(library.imageURL(for: "codex", mood: .worried), stored)
        XCTAssertFalse(FileManager.default.fileExists(atPath: library.folder(for: "codex").appendingPathComponent("worried.png").path))
    }

    func testRejectsNonImages() throws {
        let library = CharacterLibrary(root: root)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let text = root.appendingPathComponent("x.txt")
        try Data([0]).write(to: text)
        XCTAssertThrowsError(try library.importImage(from: text, providerID: "codex", mood: .normal))
    }
}
