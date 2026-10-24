import Foundation

/// Where the CodexBar CLI that Swapling runs came from.
public enum CLISource: String, Sendable {
    /// Shipped inside Swapling.app (Contents/Helpers). The normal case.
    case bundled
    /// A path the user typed in Settings.
    case custom
    /// A system install (Homebrew, CodexBar.app). Only reached when running outside the app bundle.
    case system
}

public struct ResolvedCLI: Equatable, Sendable {
    public let path: String
    public let source: CLISource

    public init(path: String, source: CLISource) {
        self.path = path
        self.source = source
    }
}

public enum CodexBarCLILocator {
    public static let helperName = "CodexBarCLI"

    /// Where users can download the CLI by hand if the bundled copy was deleted.
    public static let manualDownloadURL = URL(string: "https://github.com/steipete/CodexBar/releases/latest")!

    /// Fallbacks for `swift run`, where there is no app bundle and so no bundled helper.
    public static let systemCandidates = [
        "/opt/homebrew/bin/codexbar",
        "/usr/local/bin/codexbar",
        "/Applications/CodexBar.app/Contents/Helpers/CodexBarCLI",
    ]

    public static func bundledPath(appBundleURL: URL) -> String {
        appBundleURL
            .appendingPathComponent("Contents/Helpers", isDirectory: true)
            .appendingPathComponent(helperName)
            .path
    }

    /// Bundled helper first, then the user's custom path, then system installs.
    public static func resolve(
        appBundleURL: URL?,
        customPath: String?,
        systemCandidates: [String] = systemCandidates,
        isExecutable: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) -> ResolvedCLI? {
        if let appBundleURL {
            let bundled = bundledPath(appBundleURL: appBundleURL)
            if isExecutable(bundled) { return ResolvedCLI(path: bundled, source: .bundled) }
        }
        if let customPath = customPath?.trimmingCharacters(in: .whitespaces),
           !customPath.isEmpty, isExecutable(customPath) {
            return ResolvedCLI(path: customPath, source: .custom)
        }
        return systemCandidates.first(where: isExecutable).map { ResolvedCLI(path: $0, source: .system) }
    }
}

/// Swapling keeps its own CodexBar config so enabling providers or saving API keys here never
/// changes a separately installed CodexBar.app. The CLI is pointed at it via `CODEXBAR_CONFIG`.
public enum CodexBarConfigLocation {
    public static let environmentKey = "CODEXBAR_CONFIG"

    public enum Preparation: Equatable, Sendable {
        /// Our config already existed.
        case existing
        /// Our config was created by copying the user's CodexBar config.
        case migrated(from: URL)
        /// Neither existed; the CLI will create ours with its defaults on first write.
        case fresh
    }

    /// `~/Library/Application Support/Swapling/codexbar-config.json`
    public static func islandConfigURL(applicationSupport: URL) -> URL {
        applicationSupport
            .appendingPathComponent("Swapling", isDirectory: true)
            .appendingPathComponent("codexbar-config.json")
    }

    public static var defaultIslandConfigURL: URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return islandConfigURL(applicationSupport: support)
    }

    /// CodexBar's own config locations, current first, then legacy.
    public static func codexBarConfigURLs(home: URL) -> [URL] {
        [
            home.appendingPathComponent(".config/codexbar/config.json"),
            home.appendingPathComponent(".codexbar/config.json"),
        ]
    }

    /// Makes sure our config exists, seeding it from the user's CodexBar config the first time so
    /// existing logins and provider toggles carry over. Never touches the CodexBar config itself.
    @discardableResult
    public static func prepare(
        configURL: URL,
        seedCandidates: [URL],
        fileManager: FileManager = .default
    ) throws -> Preparation {
        if fileManager.fileExists(atPath: configURL.path) { return .existing }
        guard let source = seedCandidates.first(where: { fileManager.fileExists(atPath: $0.path) }) else {
            return .fresh
        }

        let directory = configURL.deletingLastPathComponent()
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try fileManager.copyItem(at: source, to: configURL)
        // The config can hold API keys and cookies.
        try fileManager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: configURL.path)
        return .migrated(from: source)
    }
}
