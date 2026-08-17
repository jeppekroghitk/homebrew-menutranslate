#!/usr/bin/env bash
#
# Builds MenuTranslate.app (universal by default) plus the release zip and a
# cask that installs straight from the local zip.
#
#   ./scripts/package.sh              universal arm64 + x86_64
#   NATIVE_ONLY=1 ./scripts/package.sh   this machine's architecture only
#   CODESIGN_IDENTITY="Developer ID Application: …" ./scripts/package.sh
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

APP_NAME="MenuTranslate"
BUNDLE_ID="dk.aarhus.MenuTranslate"
VERSION="$(tr -d '[:space:]' < VERSION)"
BUILD_DIR="$ROOT/build"
APP="$BUILD_DIR/$APP_NAME.app"
ZIP="$BUILD_DIR/$APP_NAME-$VERSION.zip"
IDENTITY="${CODESIGN_IDENTITY:--}"

DEPLOYMENT_TARGET="13.0"
TRIPLES=("arm64-apple-macosx$DEPLOYMENT_TARGET" "x86_64-apple-macosx$DEPLOYMENT_TARGET")
if [[ "${NATIVE_ONLY:-0}" == "1" ]]; then
	# Not `uname -m`: under Rosetta that reports x86_64 on an Apple silicon Mac.
	if [[ "$(sysctl -n hw.optional.arm64 2>/dev/null)" == "1" ]]; then
		HOST_ARCH="arm64"
	else
		HOST_ARCH="x86_64"
	fi
	TRIPLES=("$HOST_ARCH-apple-macosx$DEPLOYMENT_TARGET")
fi

# Deliberately per-triple + lipo rather than `swift build --arch a --arch b`:
# that route needs xcbuild from a full Xcode install, this one only needs the
# Command Line Tools.
SLICES=()
for triple in "${TRIPLES[@]}"; do
	echo "==> Compiling $APP_NAME $VERSION for $triple"
	swift build -c release --triple "$triple"
	SLICES+=("$(swift build -c release --triple "$triple" --show-bin-path)/$APP_NAME")
done

echo "==> Assembling bundle"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create -output "$APP/Contents/MacOS/$APP_NAME" "${SLICES[@]}"
sed -e "s/__VERSION__/$VERSION/g" -e "s/__BUNDLE_ID__/$BUNDLE_ID/g" \
	Resources/Info.plist.in > "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

# A signature — even an ad-hoc one — is required on Apple silicon and by
# SMAppService, which backs the "Launch at login" toggle.
echo "==> Signing ($IDENTITY)"
codesign --force --sign "$IDENTITY" --identifier "$BUNDLE_ID" --timestamp=none "$APP"
codesign --verify --deep --strict "$APP"

echo "==> Zipping"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
SHA="$(shasum -a 256 "$ZIP" | cut -d' ' -f1)"

# Lets you exercise the real Homebrew install path before anything is published.
# It has to sit in Casks/ because Homebrew only loads casks from a tap — see
# `make tap`. It is generated, so .gitignore keeps it out of the repo.
LOCAL_CASK="$ROOT/Casks/menutranslate-local.rb"
cat > "$LOCAL_CASK" <<CASK
cask "menutranslate-local" do
  version "$VERSION"
  sha256 "$SHA"

  url "file://$ZIP"
  name "MenuTranslate"
  desc "Menu bar popover for quick Google Translate lookups (local build)"
  homepage "https://github.com/jeppekroghitk/homebrew-menutranslate"

  depends_on macos: :ventura

  app "$APP_NAME.app"

  postflight do
    system_command "/usr/bin/xattr",
                   args: ["-dr", "com.apple.quarantine", "#{appdir}/$APP_NAME.app"]
  end

  uninstall quit: "$BUNDLE_ID"
end
CASK

ARCHS="$(lipo -archs "$APP/Contents/MacOS/$APP_NAME" 2>/dev/null || echo unknown)"

cat <<SUMMARY

    app      $APP
    zip      $ZIP
    archs    $ARCHS
    sha256   $SHA

Install it locally through Homebrew with:

    make brew-install

SUMMARY
