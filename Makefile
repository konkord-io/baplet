# Baplet developer tasks. Run `make` for an interactive menu, or `make <target>` directly.

SHELL := /bin/bash
.SHELLFLAGS := -o pipefail -c
.DEFAULT_GOAL := menu

export DEVELOPER_DIR ?= /Applications/Xcode.app/Contents/Developer

PROJECT := baplet.xcodeproj
SCHEME := baplet
DERIVED := build/DerivedData
APP := $(DERIVED)/Build/Products/Debug/Baplet.app
XCODEBUILD := xcodebuild -project $(PROJECT) -scheme $(SCHEME) -derivedDataPath $(DERIVED)
VERSION ?= 0.0.0
BUILD_NUMBER ?= 1
DMG := build/Baplet-$(VERSION).dmg

# ADHOC=1 signs without a certificate ("-"), as CI and free release builds need.
ADHOC_FLAGS := CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=
ifeq ($(ADHOC),1)
XCODEBUILD += $(ADHOC_FLAGS)
endif
PREFS := $(HOME)/Library/Preferences/io.konkord.baplet.plist
BUNDLE_ID := io.konkord.baplet

SUMMARY := awk '/error:|warning: .*\/baplet\/|BUILD (SUCCEEDED|FAILED)|TEST (SUCCEEDED|FAILED)|Test run with|✘/'
# VERBOSE=1 shows the full xcodebuild output (used in CI so failures are diagnosable).
ifeq ($(VERBOSE),1)
SUMMARY := cat
endif

.PHONY: menu run run-logs test build dmg stop clean xcode reset reset-welcome reset-settings reset-calendar reset-all

# Prints a numbered menu of the targets whose name matches $(1) (an awk regex), titled $(2),
# with $(3) as the label of the leave option, then runs the chosen target.
define pick_from
	@items=(); descs=(); \
	while IFS='|' read -r name desc; do items+=("$$name"); descs+=("$$desc"); \
	done < <(awk -F':.*## ' '/^[a-z-]+:.*## / && $$1 ~ /$(1)/ {print $$1 "|" $$2}' $(firstword $(MAKEFILE_LIST))); \
	printf '\n  \033[1m%s\033[0m\n' "$(2)"; \
	for i in "$${!items[@]}"; do printf '  \033[36m%d)\033[0m %-15s %s\n' $$((i+1)) "$${items[$$i]}" "$${descs[$$i]}"; done; \
	printf '  \033[36mq)\033[0m %s\n\n' "$(3)"; \
	read -r -p '  Choose: ' choice; \
	[[ $$choice == q || -z $$choice ]] && exit 0; \
	if [[ $$choice =~ ^[0-9]+$$ ]] && (( choice >= 1 && choice <= $${#items[@]} )); then \
		$(MAKE) --no-print-directory "$${items[$$((choice-1))]}"; \
	else printf '  Unknown choice: %s\n' "$$choice"; exit 1; fi
endef

# Asks for confirmation of $(1) unless FORCE=1; exits the recipe on anything but "y".
define confirm
	@[[ "$(FORCE)" == 1 ]] || { read -r -p "  $(1) [y/N] " answer; [[ $$answer == y || $$answer == Y ]] || { echo "  Cancelled."; exit 1; }; }
endef

menu:
	$(call pick_from,^(run|run-logs|test|build|dmg|stop|clean|xcode|reset)$$,Baplet,quit)

run: build ## Build and (re)start the app
	@pkill -x Baplet || true
	@open $(APP)
	@echo "Baplet started."

run-logs: build ## Run with NSLog output in this terminal (Ctrl-C stops)
	@pkill -x Baplet || true
	@trap 'pkill -x Baplet || true' INT TERM; open -W --stdout "$$(tty)" --stderr "$$(tty)" $(APP)

test: ## Run the unit tests
	@pkill -x Baplet || true
	@$(XCODEBUILD) -destination 'platform=macOS' test 2>&1 | $(SUMMARY)

build: ## Build the app (Debug)
	@$(XCODEBUILD) -configuration Debug build 2>&1 | $(SUMMARY)

dmg: ## Build an ad-hoc signed release DMG (VERSION=1.2.3 BUILD_NUMBER=n)
	@$(XCODEBUILD) $(ADHOC_FLAGS) -configuration Release MARKETING_VERSION=$(VERSION) CURRENT_PROJECT_VERSION=$(BUILD_NUMBER) build 2>&1 | $(SUMMARY)
	@rm -rf build/dmg-staging && mkdir -p build/dmg-staging
	@cp -R $(DERIVED)/Build/Products/Release/Baplet.app build/dmg-staging/
	@ln -s /Applications build/dmg-staging/Applications
	@hdiutil create -quiet -volname "Baplet $(VERSION)" -srcfolder build/dmg-staging -ov -format UDZO $(DMG)
	@rm -rf build/dmg-staging
	@echo "Created $(DMG) ($$(du -h $(DMG) | cut -f1))."

stop: ## Quit the running app
	@pkill -x Baplet && echo "Baplet stopped." || echo "Baplet wasn't running."

clean: ## Remove build output
	@rm -rf $(DERIVED)
	@echo "Removed $(DERIVED)."

xcode: ## Open the project in Xcode
	@open $(PROJECT)

reset: ## Reset settings, welcome guide or calendar access
	$(call pick_from,^reset-,Reset,back)

reset-welcome: ## Show the welcome guide again on next launch (clears calendar selection)
	$(call confirm,Reset the welcome guide and calendar selection?)
	@pkill -x Baplet || true
	@defaults delete $(PREFS) onboardingCompleted 2>/dev/null || true
	@defaults delete $(PREFS) enabledCalendarIDs 2>/dev/null || true
	@echo "  Welcome guide reset. It opens on the next launch (make run)."

reset-settings: ## Remove all Baplet settings (calendars, alerts, browser, shortcut, …)
	$(call confirm,Remove all Baplet settings?)
	@pkill -x Baplet || true
	@defaults delete $(PREFS) 2>/dev/null || true
	@defaults write $(PREFS) migratedFromSandboxContainer -bool true
	@echo "  Settings removed. Baplet starts fresh on the next launch (make run)."

reset-calendar: ## Revoke calendar access so macOS asks again
	$(call confirm,Revoke Baplet's calendar access?)
	@pkill -x Baplet || true
	@tccutil reset Calendar $(BUNDLE_ID)
	@echo "  Calendar access reset. macOS asks again on the next launch (make run)."

reset-all: ## All of the above
	$(call confirm,Remove all settings, the welcome state and calendar access?)
	@$(MAKE) --no-print-directory FORCE=1 reset-settings reset-calendar
