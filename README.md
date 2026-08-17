# MenuTranslate

A menu bar popover for quick Google Translate lookups. Click the icon, type, read
the translation — no button to press, no browser tab, no Dock icon.

- Translates as you type, ~450 ms after you stop.
- Remembers both languages and the last text across restarts.
- One button swaps the languages and moves the translation into the input box.
- 130 languages, searchable, with your recent ones pinned to the top.

## Install

```sh
brew tap jeppekroghitk/menutranslate
brew install --cask menutranslate
open /Applications/MenuTranslate.app
```

Homebrew asks you to trust a third-party tap once — `brew trust
jeppekroghitk/menutranslate`. The app is signed ad-hoc rather than with a paid
Developer ID, so the cask clears Gatekeeper's quarantine flag in a `postflight`
block; the comment in `Casks/menutranslate.rb` explains why.

## Usage

Click the icon and start typing. Right-click it for "Launch at login" and "Quit".

| Shortcut | Action |
| --- | --- |
| `⇧⌘S` | Swap languages |
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

Needs macOS 13+ and a Swift 5.9+ toolchain. The Command Line Tools are enough.

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

Bump `VERSION`, then tag:

```sh
git tag v0.1.0 && git push --tags
```

`.github/workflows/release.yml` builds the universal bundle, attaches the zip to a
GitHub release, and commits the real `sha256` into the cask. It fails if the tag
and `VERSION` disagree.
