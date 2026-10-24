import Foundation

/// Which face a provider's character shows, from the card's status.
public enum CharacterMood: String, CaseIterable, Sendable {
    case normal
    /// Past the first warning line.
    case worried
    /// A quota window is used up.
    case exhausted

    public init(status: ProviderStatus) {
        switch status {
        case .normal, .balance, .unconfirmed: self = .normal
        case .nearLimit: self = .worried
        case .limited: self = .exhausted
        }
    }

    public init(provider: ProviderUsage, status: ProviderStatus) {
        // Only current balance data may imply exhaustion. No universal low-money threshold.
        if status == .balance, let balance = provider.balance, balance.amount <= 0 {
            self = .exhausted
        } else {
            self.init(status: status)
        }
    }

    public var label: String {
        switch self {
        case .normal: return "正常"
        case .worried: return "紧张"
        case .exhausted: return "用完"
        }
    }
}

/// User-supplied character images, one folder per provider:
/// `~/Library/Application Support/Swapling/Characters/<providerID>/{normal,worried,exhausted}.png`.
/// User images take precedence over the app's bundled character artwork.
public struct CharacterLibrary: Sendable {
    public static let imageExtensions = ["png", "jpg", "jpeg", "gif", "heic", "webp"]

    public let root: URL
    public let bundledRoot: URL?

    public init(root: URL, bundledRoot: URL? = nil) {
        self.root = root
        self.bundledRoot = bundledRoot
    }

    public static var standard: CharacterLibrary {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return CharacterLibrary(
            root: support
                .appendingPathComponent("Swapling", isDirectory: true)
                .appendingPathComponent("Characters", isDirectory: true),
            bundledRoot: Bundle.main.resourceURL?.appendingPathComponent("Characters", isDirectory: true)
        )
    }

    public func folder(for providerID: String) -> URL {
        folder(for: providerID, in: root)
    }

    private func folder(for providerID: String, in root: URL) -> URL {
        // Provider IDs are CodexBar slugs; keep anything else from escaping the root.
        let safe = providerID.filter { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
        return root.appendingPathComponent(safe.isEmpty ? "_" : safe, isDirectory: true)
    }

    /// User overrides first, then bundled art. Account IDs inherit their base provider's art.
    public func imageURL(
        for providerID: String,
        mood: CharacterMood,
        fileExists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }
    ) -> URL? {
        let moods = mood == .normal ? [mood] : [mood, .normal]
        let base = providerID.split(separator: ":", maxSplits: 1).first.map(String.init) ?? providerID
        let ids = base == providerID ? [providerID] : [providerID, base]
        let roots = [root] + (bundledRoot.map { [$0] } ?? [])
        for source in roots {
            for id in ids {
                for candidate in moods {
                    if let url = existingImage(providerID: id, mood: candidate, root: source, fileExists: fileExists) {
                        return url
                    }
                }
            }
        }
        return nil
    }

    /// Copies `source` in as this provider's image for `mood`, replacing any earlier one.
    @discardableResult
    public func importImage(from source: URL, providerID: String, mood: CharacterMood) throws -> URL {
        let ext = source.pathExtension.lowercased()
        guard Self.imageExtensions.contains(ext) else {
            throw CocoaError(.fileReadUnsupportedScheme)
        }
        let fm = FileManager.default
        let folder = folder(for: providerID)
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        try removeImage(providerID: providerID, mood: mood)
        let target = folder.appendingPathComponent("\(mood.rawValue).\(ext)")
        try fm.copyItem(at: source, to: target)
        return target
    }

    public func removeImage(providerID: String, mood: CharacterMood) throws {
        let fm = FileManager.default
        while let url = existingImage(providerID: providerID, mood: mood, fileExists: { fm.fileExists(atPath: $0.path) }) {
            try fm.removeItem(at: url)
        }
    }

    private func existingImage(providerID: String, mood: CharacterMood, root: URL? = nil, fileExists: (URL) -> Bool) -> URL? {
        let folder = folder(for: providerID, in: root ?? self.root)
        for ext in Self.imageExtensions {
            let url = folder.appendingPathComponent("\(mood.rawValue).\(ext)")
            if fileExists(url) { return url }
        }
        return nil
    }
}
