cask "menutranslate" do
  version "0.2.0"
  sha256 "a5592114f5d2bcc4e05945b23c555b1b934882d14fb810bcaca1b034ad5ae491"

  url "https://github.com/jeppekroghitk/homebrew-menutranslate/releases/download/v#{version}/MenuTranslate-#{version}.zip"
  name "MenuTranslate"
  desc "Menu bar popover for quick Google Translate lookups"
  homepage "https://github.com/jeppekroghitk/homebrew-menutranslate"

  depends_on macos: :ventura

  app "MenuTranslate.app"

  # The app is signed ad-hoc rather than with a paid Developer ID, so Gatekeeper
  # refuses to launch it while Homebrew's quarantine flag is attached. Homebrew 6
  # dropped --no-quarantine, so the attribute is cleared here instead. Remove
  # this block if you ever sign and notarise with a Developer ID.
  postflight_steps do
    run "/usr/bin/xattr", args: ["-dr", "com.apple.quarantine", "{{appdir}}/MenuTranslate.app"]
  end

  uninstall quit: "dk.aarhus.MenuTranslate"

  zap trash: [
    "~/Library/Caches/dk.aarhus.MenuTranslate",
    "~/Library/HTTPStorages/dk.aarhus.MenuTranslate",
    "~/Library/Preferences/dk.aarhus.MenuTranslate.plist",
  ]
end
