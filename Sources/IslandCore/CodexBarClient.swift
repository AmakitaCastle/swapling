import Foundation

public enum CodexBarClientError: LocalizedError {
    case cliNotFound
    case timedOut
    case emptyOutput(stderr: String)
    case commandFailed(String)

    public var errorDescription: String? {
        switch self {
        case .cliNotFound:
            return "找不到 CodexBar 命令行工具（Swapling 自带的那份可能被删除了）。请手动下载 CodexBarCLI-macos 压缩包：\(CodexBarCLILocator.manualDownloadURL.absoluteString)，解压后在 设置 → 备用 CLI 路径 里填入其中 CodexBarCLI 的位置；或者重新安装 Swapling。"
        case .timedOut:
            return "读取额度数据超时。"
        case let .emptyOutput(stderr):
            return stderr.isEmpty ? "没有读到任何平台的数据。" : stderr
        case let .commandFailed(message):
            return message
        }
    }
}

/// Fetches usage and edits provider settings by running the CodexBar CLI bundled in the app,
/// against Swapling's own CodexBar config file.
public struct CodexBarClient: Sendable {
    public var customPath: String?
    /// Passed to the CLI as `CODEXBAR_CONFIG`; nil lets the CLI use CodexBar's default config.
    public var configURL: URL?
    public var appBundleURL: URL?
    public var timeout: TimeInterval

    public init(
        customPath: String? = nil,
        configURL: URL? = CodexBarConfigLocation.defaultIslandConfigURL,
        appBundleURL: URL? = Bundle.main.bundleURL,
        timeout: TimeInterval = 60
    ) {
        self.customPath = customPath
        self.configURL = configURL
        self.appBundleURL = appBundleURL
        self.timeout = timeout
    }

    public func resolvedCLI() -> ResolvedCLI? {
        CodexBarCLILocator.resolve(appBundleURL: appBundleURL, customPath: customPath)
    }

    public func resolvedPath() -> String? {
        resolvedCLI()?.path
    }

    // MARK: Usage

    /// Usage for the enabled providers, merged with today's cost and a 7-day trend.
    public func fetchAll() async throws -> [ProviderUsage] {
        let usageData = try await output(["usage", "--format", "json", "--no-color"], environment: storedKeyEnvironment())
        var providers = CodexBarParser.parseUsage(usageData).filter { ProviderCatalog.isVisible($0.id) }
        guard !providers.isEmpty else {
            throw CodexBarClientError.emptyOutput(stderr: "")
        }
        providers = await recoverClaude(providers)

        // Cost history only exists for some providers (local log scans); failure here is not fatal.
        if let costData = try? await output(["cost", "--format", "json", "--days", "7", "--no-color"]) {
            let formatter = DateFormatter()
            formatter.calendar = Calendar(identifier: .gregorian)
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = "yyyy-MM-dd"
            providers = CodexBarParser.attachCosts(
                CodexBarParser.parseCost(costData), to: providers, today: formatter.string(from: Date())
            )
        }
        return providers
    }

    // MARK: Claude fallback

    /// In CLI runtime CodexBar's `auto` only tries claude.ai cookies, then the `claude` PTY; it never
    /// tries Claude Code's OAuth login. When the Claude row failed and the user has not pinned a
    /// source, retry Claude with Claude Code's token (`--source oauth`) and then `--source cli`.
    func recoverClaude(_ providers: [ProviderUsage]) async -> [ProviderUsage] {
        guard providers.contains(where: { ClaudeFallback.isFailedClaudeRow($0) }),
              !ClaudeFallback.isSourcePinned(configData: configURL.flatMap { try? Data(contentsOf: $0) })
        else { return providers }

        let memory = ClaudeFallback.memory
        if memory.isCoolingDown() {
            return ClaudeFallback.explainingFailure(providers)
        }

        let credentials = ClaudeCodeCredentials.load()
        let tried = Set(providers.filter(ClaudeFallback.isFailedClaudeRow).compactMap(\.source))
        let sources = ClaudeFallback.sources(
            hasToken: credentials != nil, preferred: memory.workingSource, alreadyTried: tried
        )
        for source in sources {
            var extra: [String: String] = [:]
            if source == "oauth", let credentials {
                extra[ClaudeFallback.tokenEnvironmentKey] = credentials.accessToken
                extra[ClaudeFallback.scopesEnvironmentKey] = credentials.scopes.isEmpty
                    ? ClaudeCodeCredentials.requiredScope
                    : credentials.scopes.joined(separator: ",")
            }
            // The PTY source drives an interactive `claude` session and needs longer than the default.
            let timeout = source == "cli" ? max(self.timeout, 90) : self.timeout
            guard let result = try? await run(
                ["usage", "--provider", "claude", "--source", source, "--format", "json", "--no-color"],
                environment: extra,
                withToolPath: true,
                timeout: timeout
            ) else { continue }
            let rows = CodexBarParser.parseUsage(result.stdout)
            if let merged = ClaudeFallback.replacingFailedClaudeRows(in: providers, with: rows) {
                memory.recordSuccess(source)
                return merged
            }
        }
        memory.recordFailure()
        return ClaudeFallback.explainingFailure(providers)
    }

    /// Imports the provider's login cookies from the user's browsers. Chrome/Edge cookies are
    /// encrypted with a key in the login keychain, so this may show one macOS prompt; after
    /// "Always Allow" the CLI's background refreshes read them without asking. Only call this
    /// from a user action. Returns nil on success, otherwise a message to show.
    public func importBrowserCookies(provider id: String) async throws -> String? {
        let result = try await run(
            ["cookie", "refresh", "--provider", id, "--allow-keychain-prompt", "--format", "json"],
            timeout: max(timeout, 120)
        )
        let outcome = ClaudeFallback.cookieRefreshOutcome(result.stdout)
        if outcome.refreshed {
            ClaudeFallback.memory.reset()
            return nil
        }
        return outcome.message ?? (result.stderr.isEmpty ? "没能从浏览器导入登录。" : result.stderr)
    }

    // MARK: Provider settings

    public func providerConfigs() async throws -> [ProviderConfig] {
        let providers = try await checked(["config", "providers", "--json"])
        // Secrets in the dump are redacted unless --show-secrets is passed; we only check presence.
        let dump = try? await checked(["config", "dump", "--json"])
        return CodexBarConfigParser.parseProviders(providersJSON: providers, dumpJSON: dump)
            .filter { ProviderCatalog.isVisible($0.id) }
    }

    public func setEnabled(_ enabled: Bool, provider id: String) async throws {
        _ = try await checked(["config", enabled ? "enable" : "disable", "--provider", id, "--json"])
    }

    /// The key goes through stdin so it never shows up in the process list.
    public func setAPIKey(_ key: String, provider id: String) async throws {
        if ProviderConfig.environmentKeyNames[id] != nil {
            return try await storeEnvironmentKey(key, provider: id)
        }
        _ = try await checked(
            ["config", "set-api-key", "--provider", id, "--stdin", "--json"],
            stdin: Data(key.utf8)
        )
    }

    /// `set-api-key` rejects these providers, so enable through the CLI (which creates the entry),
    /// then write the key into that entry ourselves, keeping the file private like the CLI does.
    func storeEnvironmentKey(_ key: String, provider id: String) async throws {
        guard let configURL else {
            throw CodexBarClientError.commandFailed("没有 Swapling 自己的配置文件，无法保存 Key。")
        }
        try await setEnabled(true, provider: id)
        guard let data = try? Data(contentsOf: configURL),
              let updated = CodexBarConfigParser.settingAPIKey(key, provider: id, in: data)
        else {
            throw CodexBarClientError.commandFailed("没能把 Key 写进配置文件 \(configURL.path)。")
        }
        try updated.write(to: configURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configURL.path)
    }

    /// Keys of providers that only read them from the environment (see `environmentKeyNames`).
    func storedKeyEnvironment() -> [String: String] {
        CodexBarConfigParser.environmentKeys(configData: configURL.flatMap { try? Data(contentsOf: $0) })
    }

    // MARK: Process

    /// Directories where Homebrew, npm, bun and Claude Code's installer put CLIs.
    static func toolDirectories(home: String) -> [String] {
        [
            "\(home)/.local/bin", "\(home)/.claude/local", "\(home)/.node_modules/bin",
            "\(home)/.npm-global/bin", "\(home)/.bun/bin", "\(home)/.volta/bin",
            "/opt/homebrew/bin", "/usr/local/bin",
        ]
    }

    /// An app started from Finder only has /usr/bin:/bin:/usr/sbin:/sbin on PATH, and the CLI never
    /// asks the login shell for more, so a `claude` (or the `node` its npm launcher needs) is not
    /// found. Append the usual tool directories after the inherited ones.
    static func childEnvironment(_ base: [String: String], home: String) -> [String: String] {
        var environment = base
        var entries = (base["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin")
            .split(separator: ":").map(String.init)
        for directory in toolDirectories(home: home) where !entries.contains(directory) {
            entries.append(directory)
        }
        environment["PATH"] = entries.joined(separator: ":")
        return environment
    }

    struct RunResult {
        var stdout: Data
        var stderr: String
        var status: Int32
    }

    /// Stdout of a usage-style command. A non-zero exit still carries per-provider rows
    /// (one provider failing), so only empty output is an error.
    func output(_ arguments: [String], environment extra: [String: String] = [:]) async throws -> Data {
        let result = try await run(arguments, environment: extra)
        guard !result.stdout.isEmpty else { throw CodexBarClientError.emptyOutput(stderr: result.stderr) }
        return result.stdout
    }

    /// Stdout of a config command, which must exit 0.
    func checked(_ arguments: [String], stdin: Data? = nil) async throws -> Data {
        let result = try await run(arguments, stdin: stdin)
        guard result.status == 0 else {
            let message = CodexBarConfigParser.errorMessage(result.stdout)
                ?? (result.stderr.isEmpty ? "命令执行失败（退出码 \(result.status)）。" : result.stderr)
            throw CodexBarClientError.commandFailed(message)
        }
        return result.stdout
    }

    /// - Parameters:
    ///   - extra: Variables added to the child's environment (never logged).
    ///   - withToolPath: Let the CLI find `claude`/`node` (see `childEnvironment`). Off for the main
    ///     `usage` call: there `auto` would then drive the slow `claude` PTY on every refresh.
    func run(
        _ arguments: [String],
        stdin input: Data? = nil,
        environment extra: [String: String] = [:],
        withToolPath: Bool = false,
        timeout: TimeInterval? = nil
    ) async throws -> RunResult {
        guard let path = resolvedPath() else { throw CodexBarClientError.cliNotFound }
        var environment = ProcessInfo.processInfo.environment
        if withToolPath {
            environment = Self.childEnvironment(environment, home: FileManager.default.homeDirectoryForCurrentUser.path)
        }
        if let configURL {
            environment[CodexBarConfigLocation.environmentKey] = configURL.path
        }
        environment.merge(extra) { _, new in new }
        let timeout = timeout ?? self.timeout
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: path)
                process.arguments = arguments
                process.environment = environment
                let stdout = Pipe()
                let stderr = Pipe()
                let stdin = Pipe()
                process.standardOutput = stdout
                process.standardError = stderr
                process.standardInput = stdin

                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: error)
                    return
                }

                if let input { stdin.fileHandleForWriting.write(input) }
                try? stdin.fileHandleForWriting.close()

                let killer = DispatchWorkItem { if process.isRunning { process.terminate() } }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)

                // Read before waiting so a large payload cannot fill the pipe and deadlock.
                let out = stdout.fileHandleForReading.readDataToEndOfFile()
                let err = stderr.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                killer.cancel()

                if process.terminationReason == .uncaughtSignal {
                    continuation.resume(throwing: CodexBarClientError.timedOut)
                } else {
                    let message = String(data: err, encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    continuation.resume(returning: RunResult(stdout: out, stderr: message, status: process.terminationStatus))
                }
            }
        }
    }
}
