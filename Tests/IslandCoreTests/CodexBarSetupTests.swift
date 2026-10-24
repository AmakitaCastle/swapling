import XCTest
@testable import IslandCore

final class CodexBarCLILocatorTests: XCTestCase {
    private let app = URL(fileURLWithPath: "/Applications/Swapling.app")
    private let bundled = "/Applications/Swapling.app/Contents/Helpers/CodexBarCLI"
    private let system = ["/opt/homebrew/bin/codexbar", "/Applications/CodexBar.app/Contents/Helpers/CodexBarCLI"]

    func testBundledPath() {
        XCTAssertEqual(CodexBarCLILocator.bundledPath(appBundleURL: app), bundled)
    }

    func testPrefersBundledHelperOverEverythingElse() {
        let found = CodexBarCLILocator.resolve(
            appBundleURL: app, customPath: "/tmp/custom", systemCandidates: system, isExecutable: { _ in true }
        )
        XCTAssertEqual(found, ResolvedCLI(path: bundled, source: .bundled))
    }

    func testFallsBackToCustomPathWhenBundledMissing() {
        let found = CodexBarCLILocator.resolve(
            appBundleURL: app, customPath: "  /tmp/custom ", systemCandidates: system,
            isExecutable: { $0 != self.bundled }
        )
        XCTAssertEqual(found, ResolvedCLI(path: "/tmp/custom", source: .custom))
    }

    func testFallsBackToFirstExecutableSystemCandidate() {
        let found = CodexBarCLILocator.resolve(
            appBundleURL: nil, customPath: "", systemCandidates: system,
            isExecutable: { $0 == self.system[1] }
        )
        XCTAssertEqual(found, ResolvedCLI(path: system[1], source: .system))
    }

    func testIgnoresNonExecutableCustomPath() {
        let found = CodexBarCLILocator.resolve(
            appBundleURL: app, customPath: "/tmp/not-there", systemCandidates: system,
            isExecutable: { $0 == self.system[0] }
        )
        XCTAssertEqual(found?.source, .system)
    }

    func testNothingFoundGivesReinstallMessage() {
        let found = CodexBarCLILocator.resolve(
            appBundleURL: app, customPath: nil, systemCandidates: system, isExecutable: { _ in false }
        )
        XCTAssertNil(found)
        let message = CodexBarClientError.cliNotFound.errorDescription ?? ""
        XCTAssertTrue(message.contains("手动下载"))
        XCTAssertTrue(message.contains(CodexBarCLILocator.manualDownloadURL.absoluteString))
        XCTAssertTrue(message.contains("备用 CLI 路径"))
    }
}

final class CodexBarConfigLocationTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("SwaplingTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private var ourConfig: URL {
        CodexBarConfigLocation.islandConfigURL(applicationSupport: root.appendingPathComponent("Library/Application Support"))
    }

    private var seeds: [URL] { CodexBarConfigLocation.codexBarConfigURLs(home: root) }

    private func write(_ text: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }

    func testPaths() {
        let support = URL(fileURLWithPath: "/Users/me/Library/Application Support")
        XCTAssertEqual(
            CodexBarConfigLocation.islandConfigURL(applicationSupport: support).path,
            "/Users/me/Library/Application Support/Swapling/codexbar-config.json"
        )
        XCTAssertEqual(
            CodexBarConfigLocation.codexBarConfigURLs(home: URL(fileURLWithPath: "/Users/me")).map(\.path),
            ["/Users/me/.config/codexbar/config.json", "/Users/me/.codexbar/config.json"]
        )
    }

    func testFreshWhenNoConfigAnywhere() throws {
        XCTAssertEqual(try CodexBarConfigLocation.prepare(configURL: ourConfig, seedCandidates: seeds), .fresh)
        XCTAssertFalse(FileManager.default.fileExists(atPath: ourConfig.path))
    }

    func testMigratesCurrentCodexBarConfigFirst() throws {
        try write(#"{"current":true}"#, to: seeds[0])
        try write(#"{"legacy":true}"#, to: seeds[1])

        let result = try CodexBarConfigLocation.prepare(configURL: ourConfig, seedCandidates: seeds)

        XCTAssertEqual(result, .migrated(from: seeds[0]))
        XCTAssertEqual(try String(contentsOf: ourConfig), #"{"current":true}"#)
        let perms = try FileManager.default.attributesOfItem(atPath: ourConfig.path)[.posixPermissions] as? Int
        XCTAssertEqual(perms, 0o600)
    }

    func testMigratesLegacyConfigWhenOnlyLegacyExists() throws {
        try write(#"{"legacy":true}"#, to: seeds[1])
        XCTAssertEqual(try CodexBarConfigLocation.prepare(configURL: ourConfig, seedCandidates: seeds), .migrated(from: seeds[1]))
        XCTAssertEqual(try String(contentsOf: ourConfig), #"{"legacy":true}"#)
    }

    func testKeepsExistingConfigAndLeavesCodexBarConfigAlone() throws {
        try write(#"{"ours":true}"#, to: ourConfig)
        try write(#"{"current":true}"#, to: seeds[0])

        XCTAssertEqual(try CodexBarConfigLocation.prepare(configURL: ourConfig, seedCandidates: seeds), .existing)
        XCTAssertEqual(try String(contentsOf: ourConfig), #"{"ours":true}"#)
        XCTAssertEqual(try String(contentsOf: seeds[0]), #"{"current":true}"#)
    }
}

final class CodexBarConfigParserTests: XCTestCase {
    func testMergesToggleListWithStoredKeys() {
        let providers = Data("""
        [
          {"defaultEnabled": true, "displayName": "Codex", "enabled": true, "provider": "codex"},
          {"defaultEnabled": false, "displayName": "OpenRouter", "enabled": true, "provider": "openrouter"},
          {"defaultEnabled": false, "displayName": "Poe", "enabled": false, "provider": "poe"}
        ]
        """.utf8)
        let dump = Data("""
        {"version": 1, "providers": [
          {"id": "codex", "enabled": true},
          {"id": "openrouter", "enabled": true, "apiKey": "[REDACTED]"},
          {"id": "poe", "enabled": false, "apiKey": ""}
        ]}
        """.utf8)

        let configs = CodexBarConfigParser.parseProviders(providersJSON: providers, dumpJSON: dump)

        XCTAssertEqual(configs.map(\.id), ["codex", "openrouter", "poe"])
        XCTAssertEqual(configs.map(\.enabled), [true, true, false])
        XCTAssertEqual(configs.map(\.hasAPIKey), [false, true, false])
        XCTAssertEqual(configs.map(\.supportsAPIKey), [false, true, true])
    }

    func testMissingDumpMeansNoKnownKeys() {
        let providers = Data(#"[{"provider": "openrouter", "enabled": false}]"#.utf8)
        let configs = CodexBarConfigParser.parseProviders(providersJSON: providers, dumpJSON: nil)
        XCTAssertEqual(configs.first?.hasAPIKey, false)
        XCTAssertEqual(configs.first?.displayName, "OpenRouter")
    }

    func testReadsCLIErrorMessage() {
        let data = Data(#"[{"provider":"cli","source":"cli","error":{"code":1,"kind":"args","message":"codex does not support config API keys."}}]"#.utf8)
        XCTAssertEqual(CodexBarConfigParser.errorMessage(data), "codex does not support config API keys.")
        XCTAssertNil(CodexBarConfigParser.errorMessage(Data("not json".utf8)))
    }
}
