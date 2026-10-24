# Swapling

English · [简体中文](README.zh-CN.md)

Swapling puts your AI coding quotas in the MacBook notch. It shows how much of your 5-hour and weekly limits you have left, when they reset, and which tool to switch to when one runs out — with a little pixel-art mascot that changes mood as your quota drains.

Usage data comes from the [CodexBar](https://github.com/steipete/CodexBar) command-line tool, which ships inside the app, so you don't need to install CodexBar yourself.

> **Status: early preview (0.1.0).** The interface is in Chinese for now. This version shows **Codex (ChatGPT), Claude and DeepSeek** only; DeepSeek has not yet been fully verified with a real API key.

## Features

- **Always in the notch** — up to four pinned providers beside the notch, with a ring and percentage for the most relevant quota (5h by default, weekly when it needs attention).
- **Heads-up before you hit the limit** — when usage crosses 80% / 95% (adjustable) the island briefly expands with an alert.
- **Countdown when you're out** — once a quota is used up, the notch shows the time until it resets, and alerts you again when it does.
- **Hover or click to expand** — a panel lists every enabled provider: quota windows, reset times, balance, estimated spend today and over the last 7 days.
- **Mascot hand-over** — the panel's character follows the provider you are using; when one runs out it hands over to one that still has quota.
- **Trust signals** — stale or failed data is marked as such instead of being shown as "normal".
- Macs without a notch get a black capsule in the middle of the menu bar.

## Requirements

- A Mac with Apple silicon (M-series). Intel Macs are not supported, because the bundled CodexBar CLI is arm64 only.
- macOS 14 or later (tested on macOS 15).

## Install

Pre-built releases are not signed with an Apple Developer ID yet. After downloading from [Releases](https://github.com/AmakitaCastle/swapling/releases), macOS will refuse to open the app the first time: open **System Settings → Privacy & Security** and click **Open Anyway**.

Or build it yourself (see below).

## Getting started

1. Open Swapling, then menu bar icon → **设置… (Settings)** → **平台与 API Key (Providers & API keys)** and enable the providers you want.
2. For DeepSeek, click **填 API Key** and paste your key.
3. Codex and Claude reuse the logins already on your Mac (`codex login`, the Claude CLI, or a browser login).

### What Swapling reads on your Mac

- **Claude**: the OAuth token Claude Code stores in your login keychain (`Claude Code-credentials`), read-only and never refreshed. macOS will ask once for permission. If you choose to import browser cookies, macOS may also ask for access to your browser's cookie storage key.
- **Codex**: the login written by `codex login`.
- **API keys** you enter are stored in `~/Library/Application Support/Swapling/codexbar-config.json` (file mode 600).
- Spend figures are estimates from local Claude/Codex logs at list prices — not your bill.

Swapling itself makes no network requests and has no analytics or telemetry; usage is fetched by the bundled CodexBar CLI from each provider.

## Build from source

Requires Xcode 15+ (or a Swift 5.9+ toolchain).

```bash
swift test              # run the logic tests
swift run Swapling      # run directly (development)
./scripts/install.sh    # build, install to ~/Applications/Swapling.app and launch
```

Prefer `install.sh` over opening `dist/Swapling.app` directly: if your checkout lives in `~/Documents`, macOS asks for Documents access again after every ad-hoc-signed rebuild. `./scripts/bundle.sh` only builds the app bundle.

`scripts/fetch-codexbar-cli.sh` pins the CodexBar CLI version and SHA-256 and downloads it into `.cache/`; `bundle.sh` places it at `Swapling.app/Contents/Helpers/CodexBarCLI`.

Try the UI without real data:

```bash
~/Applications/Swapling.app/Contents/MacOS/Swapling --demo
~/Applications/Swapling.app/Contents/MacOS/Swapling --demo --demo-characters
```

## Project layout

- `Sources/IslandCore` — UI-independent logic: locating and calling the CodexBar CLI, parsing its JSON, quota status and reset rules, alerts, formatting. Covered by `Tests/IslandCoreTests`.
- `Sources/Swapling` — the notch window, island and panel views, settings.
- `Resources/Characters` — mascot artwork and the rules for swapping in your own, see [its README](Resources/Characters/README.md).

## License

Source code is released under the [MIT License](LICENSE).

The character artwork in `Resources/Characters/` is unofficial, non-commercial fan art and is **not** covered by the MIT License — see [the character artwork notice](Resources/Characters/NOTICE.md). Third-party code, the bundled CodexBar CLI and the Fusion Pixel font (SIL OFL 1.1) are listed in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

Swapling is not affiliated with OpenAI, Anthropic or DeepSeek. Provider names and icons are used only to identify where data comes from.
