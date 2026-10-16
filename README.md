# MenuTranslate

A menu bar popover for quick Google Translate lookups. Click the icon, type, read
the translation — no button to press, no browser tab, no Dock icon.

- Opens from anywhere with a global hotkey, `⌥⌘T` by default.
- Asks for the target language first: type a few letters or press `1`–`5` for a
  recent one, `↩` to keep the current one.
- Always detects the source. Text already in the target language goes to a
  fallback instead, so a Danish → English pair translates both ways untouched.
- Translates as you type, ~450 ms after you stop.
- Remembers the languages and the last text across restarts.

## Install

```sh
brew tap jeppekroghitk/menutranslate
brew install --cask menutranslate
open /Applications/MenuTranslate.app
```

Homebrew asks you to trust a third-party tap once — `brew trust
jeppekroghitk/menutranslate`. The app is signed ad-hoc rather than with a paid
Developer ID, so the cask clears Gatekeeper's quarantine flag in a
`postflight_steps` block; the comment in `Casks/menutranslate.rb` explains why.

## Usage

Press `⌥⌘T` or click the icon, pick a language, and start typing. The `⋯` menu
changes the hotkey and turns off "Choose language on open". Right-click the icon
for "Launch at login" and "Quit".

| Shortcut | Action |
| --- | --- |
| `⌥⌘T` | Open or close the panel, from any app |
| `1`–`5` | Choose a language while picking |
| `⌘L` | Choose the target language again |
| `⇧⌘C` | Copy translation |
| `⌘K` | Clear |
| `⌘↩` | Translate now, skipping the debounce |
| `esc` | Close |
| `⌘Q` | Quit |

`⌘A`, `⌘C`, `⌘V`, `⌘X` and `⌘Z` work as usual in the input box.

What you type is sent to Google when you pause, and the last text is kept in
`~/Library/Preferences/dk.aarhus.MenuTranslate.plist` so the panel can restore
it. `make reset` forgets it.

## Development

Needs macOS 13+ and a Swift 5.9+ toolchain. The Command Line Tools are enough,
with one catch: the macOS 27 SDK they ship turns SwiftUI's `@State` into a macro
whose plugin only comes with Xcode, so the build fails with "plugin for module
'SwiftUIMacros' not found". Point the build at an older SDK instead:

```sh
export SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk
```

```sh
make              # list every target
make run          # build a bundle and launch it
make app          # universal bundle, zip and local cask in build/
make brew-install # install the local build through Homebrew
```

Translation goes through `translate.googleapis.com/translate_a/single?client=gtx`,
the endpoint the Translate website itself uses: no API key, but undocumented and
rate limited per IP, hence the debounce and the response cache.

## Releasing

`VERSION` has to be committed before the tag is created: the workflow builds
from the tagged commit and fails if the tag and `VERSION` disagree.

```sh
echo 0.3.0 > VERSION
git commit -m "Bump version to 0.3.0" VERSION
git tag v0.3.0
git push origin main v0.3.0
```

`.github/workflows/release.yml` builds the universal bundle, attaches the zip to a
GitHub release, and commits the real `sha256` into the cask, so `git pull`
afterwards before changing the cask again.
