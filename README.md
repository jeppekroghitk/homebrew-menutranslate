# MenuTranslate

A menu bar popover for quick Google Translate lookups. Click the icon, type,
read the translation — no button to press, no browser tab, no Dock icon.

- Translates as you type, ~450 ms after you stop.
- Remembers both languages and the last text you typed across restarts.
- One button swaps the two languages (and moves the translation into the input
  box, so you can carry a conversation).
- "Detect language" as source, with the detected language shown in the footer.
- 130 languages, searchable, with your five most recent ones pinned to the top.

## Install with Homebrew

Once the repository is on GitHub and a release exists (see
[Cutting a release](#cutting-a-release)):

```sh
brew tap OWNER/menutranslate https://github.com/OWNER/REPO
brew install --cask menutranslate
open /Applications/MenuTranslate.app
```

Homebrew 6 refuses to load casks from untrusted third-party taps. If it asks,
trust yours once with `brew trust --tap OWNER/menutranslate`.

### Why the cask strips the quarantine flag

The app is signed ad-hoc, not with a paid Apple Developer ID, so Gatekeeper
rejects it (`spctl -a` says `rejected`) while Homebrew's quarantine flag is
attached — macOS would refuse to launch it with "Apple could not verify
MenuTranslate is free of malicious software". Homebrew 6 removed the old
`--no-quarantine` option, so the cask clears the attribute in a `postflight`
block instead. That block is the reason installing works with one command, and
it is also the one thing worth reading before you trust the tap.

The clean alternative is a Developer ID signature and notarisation, after which
the `postflight` block can be deleted — see [Signing properly](#signing-properly).

### Trying the Homebrew path before publishing

Homebrew only loads casks from a tap, so a loose `.rb` file no longer works.
`make tap` symlinks this repo in as `local/menutranslate`:

```sh
make brew-install     # builds, taps, installs from the local zip, launches
make brew-uninstall
make untap
```

## Install without Homebrew

```sh
make install     # builds and copies to /Applications, then launches it
```

## Usage

Click the menu bar icon and start typing.

| Shortcut | Action |
| --- | --- |
| `⇧⌘S` | Swap the two languages |
| `⇧⌘C` | Copy the translation |
| `⌘K` | Clear |
| `⌘↩` | Translate immediately, skipping the debounce |
| `esc` | Close the panel |
| `⌘Q` | Quit |
| `⌘A`, `⌘C`, `⌘V`, `⌘X`, `⌘Z` | Standard editing in the input box |

An accessory app shows no menu bar, but AppKit still routes ⌘-key equivalents
through `NSApp.mainMenu`. Installing a hidden main menu with an Edit menu is what
makes the standard editing shortcuts reach the text view at all — without it
`⌘A` and friends are silently dropped.

Right-click the menu bar icon for "Launch at login" and "Quit" without opening
the panel. The `⋯` menu inside the panel has the same options plus "Open in
Google Translate", which hands the current text off to the website.

Preferences live in `~/Library/Preferences/dk.aarhus.MenuTranslate.plist`.
`make reset` forgets them.

## Development

```sh
make              # list every target
make build        # debug build
make run          # build a bundle and launch it
make app          # universal (arm64 + x86_64) bundle, zip and local cask
make app-native   # same, this machine's architecture only — quicker
make uninstall
make clean
```

Requires macOS 13 or newer and a Swift 5.9+ toolchain. The Command Line Tools
are enough; a full Xcode install is not needed. That is why `package.sh` builds
one slice per architecture and joins them with `lipo` rather than using
`swift build --arch arm64 --arch x86_64`, which needs xcbuild from a full Xcode.

Both the script and the Makefile detect a Rosetta shell — `uname -m` reports
`x86_64` there even on Apple silicon, and Homebrew in `/opt/homebrew` refuses to
run at all.

The app is a plain SwiftPM executable that `scripts/package.sh` wraps into an
`.app` bundle, because `LSUIElement`, `SMAppService` and Homebrew casks all need
a real bundle. Layout:

| Path | Purpose |
| --- | --- |
| `Sources/MenuTranslate/AppDelegate.swift` | Status item, popover, panel-wide keys |
| `Sources/MenuTranslate/TranslatePanel.swift` | The popover UI |
| `Sources/MenuTranslate/LanguagePicker.swift` | Searchable language list |
| `Sources/MenuTranslate/TranslatorModel.swift` | Debounce, cache, persistence, swap |
| `Sources/MenuTranslate/TranslationService.swift` | The Google Translate call |
| `Sources/MenuTranslate/Language.swift` | Language table |
| `Resources/Info.plist.in` | Bundle metadata template |
| `scripts/package.sh` | Bundle, sign, zip |
| `Casks/menutranslate.rb` | Homebrew cask |

### How translation works

Requests go to `translate.googleapis.com/translate_a/single?client=gtx`, the
endpoint the Google Translate website itself uses. No API key and no billing
account, which is the whole reason this app can be installed with one command.
The trade-offs:

- It is undocumented and Google can change or withdraw it.
- It is rate limited per IP address. Hence the debounce, and a response cache so
  swapping back and forth does not re-request. A `429` surfaces in the footer as
  "Google is rate limiting this Mac".
- Text is capped at 5000 characters, the endpoint's own limit.

Switching to the official Cloud Translation API means changing only
`TranslationService.translate` and adding somewhere to keep the API key.

### Text sent to Google

Whatever you type in the panel is sent to Google as soon as you pause, exactly
as it would be on translate.google.com. The last text you typed is also stored
in plain text in the preferences plist so the panel can restore it. Don't paste
secrets into it.

## Cutting a release

1. Bump `VERSION`.
2. Commit, then tag: `git tag v0.1.0 && git push --tags`.
3. `.github/workflows/release.yml` builds a universal bundle, attaches the zip
   to a GitHub release, and commits the matching `version`/`sha256` back into
   `Casks/menutranslate.rb`. The digest can only be computed from the artefact
   CI itself built, which is why the cask is updated there rather than by hand.

The workflow fails if the tag and `VERSION` disagree. The `OWNER/REPO`
placeholders in the cask and in this README are rewritten on the first release.

### Signing properly

Ad-hoc signing is the default so that a build works with no Apple account. With
a paid Developer ID you can delete the cask's `postflight` block:

```sh
CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" make app
xcrun notarytool submit build/MenuTranslate-0.1.0.zip --apple-id … --team-id … --password …
xcrun stapler staple build/MenuTranslate.app
```

## Known gaps

- No app icon, so the Finder and Login Items show a generic one. It never
  appears in the Dock, so this is mostly cosmetic.
- No global hotkey to open the panel; that needs Accessibility permission.
- Text-to-speech, alternative translations and dictionary entries are not shown,
  though the endpoint can return them.
