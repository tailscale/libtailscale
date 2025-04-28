# Copyright (c) Tailscale Inc & AUTHORS
# SPDX-License-Identifier: BSD-3-Clause

## Prettifies xcode output for xcode tests using xcpretty, if it is installed
XCPRETTIFIER := xcpretty
ifeq (, $(shell which $(XCPRETTIFIER)))
        XCPRETTIFIER := cat
endif

# The xcodebuild schemes will run the Makefile in the root directory to build
# the libtailscale.a and libtailscale_ios.a dependencies.

.PHONY: macos
macos:  ## Builds TailscaleKit for macos to swift/build/Build/Products/Release (unsigned)
	cd .. && make c-archive
	mkdir -p build
	xcodebuild build -scheme "TailscaleKit (macOS)" \
	 -derivedDataPath build \
	 -configuration Release \
	 -destination 'platform=macOS,arch=arm64' \
	 CODE_SIGNING_ALLOWED=NO | $(XCPRETTIFIER)

.PHONY: ios
ios:  ## Builds TailscaleKit for iOS to swift/build/Build/Products/Release (unsigned)
	cd .. && make c-archive-ios
	mkdir -p build
	xcodebuild build -scheme "TailscaleKit (iOS)" \
	 -derivedDataPath build \
	 -configuration Release \
	 -destination 'generic/platform=iOS' \
	 CODE_SIGNING_ALLOWED=NO | $(XCPRETTIFIER)


.PHONY: test
test: ## Run tests (macOS)
	cd .. && make c-archive
	mkdir -p build
	xcodebuild test -scheme TailscaleKitXCTests \
	 -derivedDataPath build \
	 -configuration Debug \
	 -destination 'platform=macOS,arch=arm64' | $(XCPRETTIFIER)

.PHONY: clean
clean: ## Clean up build artifacts (including the libtailscale dependencies)
	cd .. && make clean
	rm -rf build 

.PHONY: help
help: ## Show this help
	@echo "\nSpecify a command. The choices are:\n"
	@grep -hE '^[0-9a-zA-Z_-]+:.*?## .*$$' ${MAKEFILE_LIST} | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[0;36m%-12s\033[m %s\n", $$1, $$2}'
	@echo ""

.DEFAULT_GOAL := help
