import Foundation

/// One provider as Swapling's CodexBar config sees it, for the Settings page.
public struct ProviderConfig: Identifiable, Equatable, Sendable {
    public let id: String
    public let displayName: String
    public var enabled: Bool
    /// The config already holds an API key for this provider (the value itself is never read).
    public var hasAPIKey: Bool

    public init(id: String, displayName: String, enabled: Bool, hasAPIKey: Bool) {
        self.id = id
        self.displayName = displayName
        self.enabled = enabled
        self.hasAPIKey = hasAPIKey
    }

    public var supportsAPIKey: Bool {
        ProviderConfig.apiKeyProviderIDs.contains(id) || ProviderConfig.environmentKeyNames[id] != nil
    }

    /// Providers whose CLI fetcher reads the key only from an environment variable: `set-api-key`
    /// rejects them ("does not support config API keys"). Swapling keeps their key in the
    /// provider's `apiKey` field of its own config (the CLI leaves it alone) and passes it as this
    /// variable on each usage run.
    public static let environmentKeyNames: [String: String] = ["deepseek": "DEEPSEEK_API_KEY"]

    /// Providers whose `codexbar config set-api-key` succeeds in CodexBar CLI 0.77.0 (probed against
    /// a scratch config). Re-check when bumping the version in scripts/fetch-codexbar-cli.sh.
    public static let apiKeyProviderIDs: Set<String> = [
        "openai", "azureopenai", "claude", "clinepass", "opencodego", "alibaba", "factory", "fireworks",
        "copilot", "zai", "minimax", "kimi", "kilo", "moonshot", "amp", "ollama", "synthetic", "openrouter",
        "elevenlabs", "warp", "doubao", "deepinfra", "codebuff", "venice", "commandcode", "groq", "llmproxy",
        "litellm", "bifrost", "aixy", "deepgram", "poe", "chutes", "neuralwatt", "clawrouter", "sub2api",
        "zenmux", "aiand", "xai", "ibmbob", "huggingface", "v0", "hyper", "gitkraken", "futureagi", "devpass",
        "atlascloud", "vercel", "llmman", "xkiro", "tavily", "linkup", "exa", "cosmic", "aerostack",
        "sailresearch", "sofya", "fal", "flora", "munito",
    ]
}

public enum CodexBarConfigParser {
    private struct ProviderRow: Decodable {
        let provider: String
        let displayName: String?
        let enabled: Bool?
    }

    private struct Dump: Decodable {
        struct Provider: Decodable {
            let id: String
            let apiKey: String?
        }
        let providers: [Provider]?
    }

    private struct ErrorRow: Decodable {
        struct Detail: Decodable { let message: String? }
        let error: Detail?
    }

    /// Combines `config providers --json` (names, toggles) with `config dump --json`
    /// (redacted secrets, used only to tell whether a key is stored).
    public static func parseProviders(providersJSON: Data, dumpJSON: Data?) -> [ProviderConfig] {
        let rows = (try? JSONDecoder().decode([ProviderRow].self, from: providersJSON)) ?? []
        var keyed = Set<String>()
        if let dumpJSON, let dump = try? JSONDecoder().decode(Dump.self, from: dumpJSON) {
            for provider in dump.providers ?? [] where !(provider.apiKey ?? "").isEmpty {
                keyed.insert(provider.id)
            }
        }
        return rows.map { row in
            ProviderConfig(
                id: row.provider,
                displayName: row.displayName ?? ProviderCatalog.displayName(for: row.provider),
                enabled: row.enabled ?? false,
                hasAPIKey: keyed.contains(row.provider)
            )
        }
    }

    /// Environment for a usage run: each `environmentKeyNames` provider's stored key, by variable name.
    public static func environmentKeys(configData: Data?) -> [String: String] {
        guard let configData,
              let root = try? JSONSerialization.jsonObject(with: configData) as? [String: Any],
              let providers = root["providers"] as? [[String: Any]]
        else { return [:] }
        var environment: [String: String] = [:]
        for provider in providers {
            guard let id = provider["id"] as? String, let name = ProviderConfig.environmentKeyNames[id],
                  let key = provider["apiKey"] as? String, !key.isEmpty
            else { continue }
            environment[name] = key
        }
        return environment
    }

    /// The config with `key` stored as the provider's `apiKey`, every other field untouched.
    /// The provider must already have an entry (enable it through the CLI first).
    public static func settingAPIKey(_ key: String, provider id: String, in configData: Data) -> Data? {
        guard var root = try? JSONSerialization.jsonObject(with: configData) as? [String: Any],
              var providers = root["providers"] as? [[String: Any]],
              let index = providers.firstIndex(where: { $0["id"] as? String == id })
        else { return nil }
        providers[index]["apiKey"] = key
        root["providers"] = providers
        return try? JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
    }

    /// The CLI reports failures as `[{"error": {"message": …}}]` on stdout.
    public static func errorMessage(_ data: Data) -> String? {
        if let rows = try? JSONDecoder().decode([ErrorRow].self, from: data) {
            return rows.compactMap { $0.error?.message }.first
        }
        if let row = try? JSONDecoder().decode(ErrorRow.self, from: data) {
            return row.error?.message
        }
        return nil
    }
}
