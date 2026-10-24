# Third-party notices

## Character artwork
The fan artwork in `Resources/Characters/` (shipped as `Contents/Resources/Characters`) is not
covered by the MIT License; see `Resources/Characters/NOTICE.md` for credits and terms.

## CodeIsland
`Sources/Swapling/IslandShape.swift` (`IslandShape`) and the spring values in `IslandAnimation`
are adapted from CodeIsland: https://github.com/wxtsky/CodeIsland

MIT License

Copyright (c) 2026 wxtsky

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

## CodexBar
Swapling.app redistributes the CodexBar command-line tool (https://github.com/steipete/CodexBar)
as `Contents/Helpers/CodexBarCLI`, together with its resource bundle
(`Contents/Resources/CodexBar_CodexBarCore.bundle`). The binary is the unmodified upstream
release `CodexBarCLI-v0.77.0-macos-arm64.tar.gz`, ad-hoc re-signed inside the app
(see `scripts/fetch-codexbar-cli.sh`). The notices for CodexBar's own
dependencies ship unchanged as `Contents/Resources/CodexBarCLI-THIRD_PARTY_NOTICES.txt`.
The JSON field names in `Sources/IslandCore/CodexBarPayload.swift` follow its documented CLI output.
The provider icons in `Resources/ProviderIcons/ProviderIcon-*.svg` (shipped as
`Contents/Resources/ProviderIcons`) are copied unmodified from CodexBar v0.77.0
(`Sources/CodexBar/Resources`); the brand colors they are tinted with in
`Sources/IslandCore/ProviderIconName.swift` come from its provider descriptors.

MIT License

Copyright (c) 2026 Peter Steinberger

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.

## Fusion Pixel Font
`Resources/Fonts/FusionPixel-12px-Proportional-zh_hans.otf` (shipped as
`Contents/Resources/Fonts`) is the unmodified `fusion-pixel-12px-proportional-zh_hans.otf` from
Fusion Pixel Font release 2026.10.16 (https://github.com/TakWolf/fusion-pixel-font), renamed only.
It is licensed under the SIL Open Font License, Version 1.1; the full license text ships next to it
as `FusionPixel-OFL.txt`, and the licenses of the fonts it merges (Ark Pixel Font, Cubic 11,
Galmuri) as `FusionPixel-LICENSES/`.

Copyright (c) 2022, TakWolf (https://takwolf.com).
