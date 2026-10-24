import XCTest
@testable import IslandCore

final class ProviderVisibilityTests: XCTestCase {
    func testOnlyGPTClaudeAndDeepSeekAreVisible() {
        for id in ["codex", "openai", "claude", "claude:work", "deepseek"] {
            XCTAssertTrue(ProviderCatalog.isVisible(id), id)
        }
        for id in ["gemini", "cursor", "openrouter", "kimi"] {
            XCTAssertFalse(ProviderCatalog.isVisible(id), id)
        }
    }

    func testDeepSeekTakesAKeyThroughTheEnvironment() {
        let config = ProviderConfig(id: "deepseek", displayName: "DeepSeek", enabled: true, hasAPIKey: false)
        XCTAssertTrue(config.supportsAPIKey)
    }

    func testStoredDeepSeekKeyBecomesItsEnvironmentVariable() throws {
        let config = Data(#"{"providers": [{"id": "codex", "enabled": true}, {"id": "deepseek", "enabled": true}], "version": 1}"#.utf8)
        let updated = try XCTUnwrap(CodexBarConfigParser.settingAPIKey("sk-abc", provider: "deepseek", in: config))
        XCTAssertEqual(CodexBarConfigParser.environmentKeys(configData: updated), ["DEEPSEEK_API_KEY": "sk-abc"])

        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: updated) as? [String: Any])
        XCTAssertEqual(root["version"] as? Int, 1)
        XCTAssertEqual((root["providers"] as? [[String: Any]])?.count, 2)
    }

    func testOtherProvidersKeysAreNotExported() {
        let config = Data(#"{"providers": [{"id": "openrouter", "apiKey": "sk-or"}, {"id": "deepseek", "apiKey": ""}]}"#.utf8)
        XCTAssertEqual(CodexBarConfigParser.environmentKeys(configData: config), [:])
    }

    func testSettingAKeyNeedsTheProviderEntry() {
        let config = Data(#"{"providers": [{"id": "codex"}]}"#.utf8)
        XCTAssertNil(CodexBarConfigParser.settingAPIKey("sk", provider: "deepseek", in: config))
    }
}
