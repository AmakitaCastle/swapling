import IslandCore
import XCTest

final class ProviderIconNameTests: XCTestCase {
    func testPlainAndAccountScopedIds() {
        XCTAssertEqual(ProviderIconName.resourceName(for: "claude"), "ProviderIcon-claude")
        XCTAssertEqual(ProviderIconName.resourceName(for: "codex:work"), "ProviderIcon-codex")
    }

    func testAliases() {
        XCTAssertEqual(ProviderIconName.resourceName(for: "openai"), "ProviderIcon-codex")
        XCTAssertEqual(ProviderIconName.resourceName(for: "moonshot"), "ProviderIcon-kimi")
    }

    func testBrandColors() {
        XCTAssertEqual(ProviderIconName.brandColor(for: "claude"), 0xCC7C5E)
        XCTAssertEqual(ProviderIconName.brandColor(for: "codex:work"), 0x49A3B0)
        XCTAssertNil(ProviderIconName.brandColor(for: "workbuddy"))
    }

    func testCatalogProvidersHaveBundledIcons() throws {
        let dir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/ProviderIcons")
        for id in ["claude", "codex", "openai", "cursor", "gemini", "copilot", "openrouter", "zai", "kimi",
                   "moonshot", "deepseek", "doubao", "qwencloud", "antigravity", "grok", "windsurf",
                   "minimax", "factory", "amp", "kiro", "workbuddy"] {
            let file = dir.appendingPathComponent(ProviderIconName.resourceName(for: id) + ".svg")
            XCTAssertTrue(FileManager.default.fileExists(atPath: file.path), "missing icon for \(id)")
        }
    }
}
