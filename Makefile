APP_NAME := MenuTranslate
BUNDLE_ID := dk.aarhus.MenuTranslate
VERSION := $(shell tr -d '[:space:]' < VERSION)
APP := build/$(APP_NAME).app
TAP := local/menutranslate
TAP_DIR := $(shell brew --repository 2>/dev/null)/Library/Taps/local/homebrew-menutranslate

# Homebrew in /opt/homebrew refuses to run from a Rosetta shell, which is easy
# to end up in without noticing.
BREW := $(shell test "$$(sysctl -n sysctl.proc_translated 2>/dev/null)" = 1 && echo "arch -arm64 brew" || echo brew)

.DEFAULT_GOAL := help

.PHONY: help
help: ## Show available targets
	@grep -hE '^[a-z-]+:.*?## ' $(MAKEFILE_LIST) | awk -F':.*?## ' '{printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

.PHONY: build
build: ## Compile a debug binary
	swift build

.PHONY: app
app: ## Build the universal .app bundle and release zip in build/
	./scripts/package.sh

.PHONY: app-native
app-native: ## Same as app, but only for this machine's architecture (faster)
	NATIVE_ONLY=1 ./scripts/package.sh

.PHONY: run
run: app-native ## Build and launch the app
	@pkill -x $(APP_NAME) || true
	open $(APP)

.PHONY: install
install: app-native ## Copy the app to /Applications and launch it
	@pkill -x $(APP_NAME) || true
	rm -rf /Applications/$(APP_NAME).app
	cp -R $(APP) /Applications/
	open /Applications/$(APP_NAME).app
	@echo "Installed /Applications/$(APP_NAME).app"

.PHONY: tap
tap: ## Expose this repo to Homebrew as the local/menutranslate tap
	@mkdir -p $(dir $(TAP_DIR))
	@ln -sfn $(CURDIR) $(TAP_DIR)
	@echo "Tapped $(TAP) -> $(CURDIR)"

.PHONY: untap
untap: ## Remove the local tap
	rm -f $(TAP_DIR)

.PHONY: brew-install
brew-install: app tap ## Install the local build through Homebrew, as a real user would
	-$(BREW) uninstall --cask --force $(TAP)/menutranslate-local
	@# The file:// download is cached by URL, so a rebuilt zip at the same
	@# version would otherwise fail Homebrew's checksum against a stale copy.
	-rm -f "$$($(BREW) --cache --cask $(TAP)/menutranslate-local 2>/dev/null)"
	$(BREW) install --cask $(TAP)/menutranslate-local
	open /Applications/$(APP_NAME).app

.PHONY: brew-uninstall
brew-uninstall: ## Remove a Homebrew-installed local build
	$(BREW) uninstall --cask --force --zap $(TAP)/menutranslate-local

.PHONY: uninstall
uninstall: ## Remove the app and its preferences
	@pkill -x $(APP_NAME) || true
	rm -rf /Applications/$(APP_NAME).app
	defaults delete $(BUNDLE_ID) 2>/dev/null || true

.PHONY: reset
reset: ## Forget stored languages and text
	defaults delete $(BUNDLE_ID) 2>/dev/null || true

.PHONY: clean
clean: ## Remove build artefacts
	rm -rf .build build
