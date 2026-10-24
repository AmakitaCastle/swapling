import Foundation

/// Maps provider ids to the monochrome SVGs copied from CodexBar into `Resources/ProviderIcons`.
public enum ProviderIconName {
    /// Providers that use another provider's artwork (CodexBar draws OpenAI with the Codex mark).
    private static let aliases: [String: String] = [
        "openai": "codex",
        "moonshot": "kimi",
    ]

    /// Brand colors from CodexBar v0.77.0's provider descriptors (`ProviderBranding.color`), as
    /// 0xRRGGBB. Near-black colors are left out because they'd vanish on the black island.
    private static let brandColors: [String: UInt32] = [
        "abacus": 0x814EE8,
        "alibaba": 0xFF6A00,
        "alibabatokenplan": 0xFF6A00,
        "amp": 0xF34E3F,
        "antigravity": 0x60BA7E,
        "augment": 0x1AA049,
        "azureopenai": 0x0078D4,
        "bedrock": 0x01A88D,
        "claude": 0xCC7C5E,
        "codebuff": 0x00FF95,
        "coderabbit": 0xFF5C35,
        "codex": 0x49A3B0,
        "commandcode": 0x8C4EDD,
        "copilot": 0xA855F7,
        "cursor": 0xF54E00,
        "deepseek": 0x4D6BFE,
        "devin": 0x317CFF,
        "doubao": 0x3370FF,
        "factory": 0xFF6B35,
        "gemini": 0xAB87EA,
        "grok": 0x10A37F,
        "groq": 0xF56844,
        "ibmbob": 0x0E61FA,
        "jetbrains": 0xFF3399,
        "kilo": 0xF27027,
        "kimi": 0xFE603C,
        "kiro": 0x9046FF,
        "longcat": 0x29E154,
        "mimo": 0xFF6900,
        "minimax": 0xFE603C,
        "mistral": 0xFF5229,
        "moonshot": 0x205DEB,
        "muse": 0x0668E1,
        "ollama": 0x888888,
        "openai": 0x0F826E,
        "opencode": 0x3B82F6,
        "opencodego": 0x3B82F6,
        "openrouter": 0x6467F2,
        "pi": 0x7C3AED,
        "qwencloud": 0x615CED,
        "stepfun": 0x2196F2,
        "vertexai": 0x4285F4,
        "warp": 0x938BB4,
        "wayfinder": 0x10A37F,
        "windsurf": 0x34E8BB,
        "zai": 0xE85A6A,
    ]

    /// Brand color for a plain or account-scoped id, or nil to keep the neutral foreground.
    public static func brandColor(for id: String) -> UInt32? {
        brandColors[baseID(id)]
    }

    private static func baseID(_ id: String) -> String {
        (id.split(separator: ":").first.map(String.init) ?? id).lowercased()
    }

    /// Accepts plain and account-scoped ids ("claude:work"); whether the file exists is up to the caller.
    public static func resourceName(for id: String) -> String {
        let base = baseID(id)
        return "ProviderIcon-" + (aliases[base] ?? base)
    }
}
