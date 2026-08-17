cask "menutranslate" do
  version "0.1.0"
  sha256 :no_check

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
  postflight do
    system_command "/usr/bin/xattr",
                   args: ["-dr", "com.apple.quarantine", "#{appdir}/MenuTranslate.app"]
  end

  uninstall quit: "dk.aarhus.MenuTranslate"

  zap trash: [
    "~/Library/Caches/dk.aarhus.MenuTranslate",
    "~/Library/HTTPStorages/dk.aarhus.MenuTranslate",
    "~/Library/Preferences/dk.aarhus.MenuTranslate.plist",
  ]
end
