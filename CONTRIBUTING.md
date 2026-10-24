# Contributing to Swapling

Thanks for your interest! Issues and pull requests are welcome, in English or Chinese.

## Development setup

- Apple silicon Mac, macOS 14+, Xcode 15+ (or a Swift 5.9+ toolchain).
- `swift test` runs the logic tests in `Tests/IslandCoreTests`.
- `./scripts/install.sh` builds the app, installs it to `~/Applications/Swapling.app` and launches it.
- `--demo` (and `--demo --demo-characters`) shows fixed sample data, so you can check the UI without hitting real limits.

## Guidelines

- Put logic that does not need the UI in `Sources/IslandCore` and cover it with tests; keep `Sources/Swapling` for views and system integration.
- Keep pull requests focused, and describe what a user would see before and after the change. Screenshots help for UI changes — please take them in `--demo` mode so no real account data appears.
- Never commit API keys, tokens, cookies or screenshots that show personal data.
- Do not add artwork you do not have the right to distribute. Code contributions are accepted under the MIT License; character art follows [Resources/Characters/NOTICE.md](Resources/Characters/NOTICE.md).

## Reporting bugs

Use the bug report template and include the Swapling version, macOS version, which providers are enabled, and what you expected. Remove keys and account details from any logs before posting.
