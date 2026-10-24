import Foundation

/// Claude Code's own OAuth login, read without prompting so the CodexBar CLI can use it
/// (`--source oauth` with `CODEXBAR_CLAUDE_OAUTH_TOKEN`) when no claude.ai cookie is around.
///
/// The token is only ever read, never refreshed: refreshing would rotate Claude Code's refresh
/// token and sign Claude Code out. When it has expired, running `claude` renews it.
public struct ClaudeCodeCredentials: Equatable, Sendable {
    public let accessToken: String
    public let scopes: [String]
    public let expiresAt: Date?

    /// Scope the usage endpoint needs.
    public static let requiredScope = "user:profile"
    static let keychainService = "Claude Code-credentials"

    /// Valid credentials from the keychain item Claude Code writes, falling back to its
    /// `.credentials.json` (used on machines without a login keychain).
    public static func load(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        now: Date = Date()
    ) -> ClaudeCodeCredentials? {
        if let data = readKeychain(), let credentials = parse(data, now: now) {
            return credentials
        }
        for url in credentialFileURLs(environment: environment, home: home) {
            if let data = try? Data(contentsOf: url), let credentials = parse(data, now: now) {
                return credentials
            }
        }
        return nil
    }

    static func credentialFileURLs(environment: [String: String], home: URL) -> [URL] {
        var urls: [URL] = []
        if let dir = environment["CLAUDE_CONFIG_DIR"], !dir.isEmpty {
            urls.append(URL(fileURLWithPath: dir).appendingPathComponent(".credentials.json"))
        }
        urls.append(home.appendingPathComponent(".claude/.credentials.json"))
        return urls
    }

    private struct File: Decodable {
        struct OAuth: Decodable {
            let accessToken: String?
            /// Milliseconds since 1970.
            let expiresAt: Double?
            let scopes: [String]?
        }
        let claudeAiOauth: OAuth?
    }

    /// The access token if it is still good for at least a minute and carries `user:profile`
    /// (when scopes are listed at all).
    public static func parse(_ data: Data, now: Date = Date()) -> ClaudeCodeCredentials? {
        guard let file = try? JSONDecoder().decode(File.self, from: data),
              let oauth = file.claudeAiOauth,
              let token = oauth.accessToken?.trimmingCharacters(in: .whitespacesAndNewlines),
              !token.isEmpty
        else { return nil }

        let expiresAt = oauth.expiresAt.map { Date(timeIntervalSince1970: $0 / 1000) }
        if let expiresAt, expiresAt.timeIntervalSince(now) < 60 { return nil }

        let scopes = oauth.scopes ?? []
        if oauth.scopes != nil, !scopes.contains(requiredScope) { return nil }
        return ClaudeCodeCredentials(accessToken: token, scopes: scopes, expiresAt: expiresAt)
    }

    /// Claude Code stores the item through /usr/bin/security, so the same tool reads it back
    /// without a keychain prompt.
    static func readKeychain(timeout: TimeInterval = 5) -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", keychainService, "-w"]
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let killer = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)
        let data = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        killer.cancel()
        guard process.terminationReason == .exit, process.terminationStatus == 0, !data.isEmpty else { return nil }
        return data
    }
}
