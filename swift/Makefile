# Copyright (c) Tailscale Inc & AUTHORS
# SPDX-License-Identifier: BSD-3-Clause

## Prettifies xcode output for xcode tests using xcpretty, if it is installed
XCPRETTIFIER := xcpretty
ifeq (, $(shell which $(XCPRETTIFIER)))
        XCPRETTIFIER := cat
endif

# The xcodebuild schemes will run the Makefile in the root directory to build
# the libtailscale.a and libtailscale_ios.a dependencies.

.PHONY: all
all: test ios macos ios-fat  ## Runs the tests and builds all library targets

.PHONY: macos
macos:  ## Builds TailscaleKit for macos to swift/build/Build/Products/Release (unsigned)
	@echo
	@echo "::: Building TailscaleKit.framework for macOS :::"
	cd .. && make c-archive
	mkdir -p build
	xcodebuild build -scheme "TailscaleKit (macOS)" \
	 -derivedDataPath build \
	 -configuration Release \
	 -destination 'platform=macOS,arch=arm64' \
	 CODE_SIGNING_ALLOWED=NO | $(XCPRETTIFIER)

.PHONY: ios
ios:  ## Builds TailscaleKit for iOS to swift/build/Build/Products/Release-iphoneos (unsigned)
	@echo
	@echo "::: Building TailscaleKit.framework for iOS :::"
	cd .. && make c-archive-ios
	mkdir -p build
	xcodebuild build -scheme "TailscaleKit (iOS)" \
	 -derivedDataPath build \
	 -configuration Release \
	 -destination 'generic/platform=iOS' \
	 CODE_SIGNING_ALLOWED=NO | $(XCPRETTIFIER)

.PHONY: ios-sim
ios-sim:  ## Builds TailscaleKit for iOS to swift/build/Build/Products/Release-iphonesimulator (unsigned)
	@echo
	@echo "::: Building TailscaleKit.framework for iOS Simulator :::"
	cd .. && make c-archive-ios-sim
	mkdir -p build
	xcodebuild build -scheme "TailscaleKit (Simulator)" \
	 -derivedDataPath build \
	 -configuration Release \
	 -destination 'generic/platform=iOS Simulator' \
	 CODE_SIGNING_ALLOWED=NO | $(XCPRETTIFIER)

.PHONY: ios-fat
ios-fat: ios-sim ios ## Builds TailscaleKit.xcframework (iOS + simulator) to swift/build/Build/Products/Release-iphonefat
	@echo 
	@echo "::: Building TailscaleKit.xcframework for ios and ios-simulator :::"
	$(MAKE) inject-privacy-manifest-ios
	mkdir -p ./build/Build/Products/Release-iphonefat
	xcodebuild -create-xcframework \
		-framework ./build/Build/Products/Release-iphoneos/TailscaleKit.framework \
		-framework ./build/Build/Products/Release-iphonesimulator/TailscaleKit.framework \
		-output ./build/Build/Products/Release-iphonefat/TailscaleKit.xcframework

# The simulator slice belongs in a distributable xcframework and does not put an
# App Store submission at risk. An xcframework is a container, not the submitted
# artifact: Xcode resolves it at build time and embeds only the slice matching the
# destination, so an app archived for the App Store carries the ios-arm64 slice
# alone. The rule people remember — "no simulator binaries in a submission" — comes
# from fat frameworks, where lipo put device and simulator architectures in one
# binary with no way for Xcode to pick one. That is the problem xcframeworks exist
# to solve, and it is why "ios" and "ios-sim" are separate targets here.
#
# What does need checking is that each slice is genuinely what its name says;
# script/validate-xcframework.sh verifies the build platform of every architecture
# in every slice, so simulator code cannot reach a device slice unnoticed.
.PHONY: xcframework
xcframework: ios-sim ios macos ## Builds a distributable 3-slice TailscaleKit.xcframework (iOS + simulator + macOS)
	@echo
	@echo "::: Building distributable TailscaleKit.xcframework (ios, ios-simulator, macos) :::"
	$(MAKE) inject-privacy-manifest-ios
	$(MAKE) inject-privacy-manifest-macos
	mkdir -p ./build/Build/Products/Release-all
	xcodebuild -create-xcframework \
		-framework ./build/Build/Products/Release-iphoneos/TailscaleKit.framework \
		-framework ./build/Build/Products/Release-iphonesimulator/TailscaleKit.framework \
		-framework ./build/Build/Products/Release/TailscaleKit.framework \
		-output ./build/Build/Products/Release-all/TailscaleKit.xcframework
	@echo "Wrote ./build/Build/Products/Release-all/TailscaleKit.xcframework"
	@echo "Validate before distributing:  ./script/validate-xcframework.sh ./build/Build/Products/Release-all/TailscaleKit.xcframework"

# Apple rejects an app at UPLOAD (ITMS-91053), not at build, if an embedded
# iOS framework slice has no PrivacyInfo.xcprivacy. TailscaleKit collects
# nothing, but the manifest still has to be present.
.PHONY: inject-privacy-manifest-ios
inject-privacy-manifest-ios:
	@for fw in ./build/Build/Products/Release-iphoneos/TailscaleKit.framework \
	           ./build/Build/Products/Release-iphonesimulator/TailscaleKit.framework; do \
		if [ -d "$$fw" ]; then \
			cp ./PrivacyInfo.xcprivacy "$$fw/PrivacyInfo.xcprivacy"; \
			echo "Injected PrivacyInfo.xcprivacy -> $$fw"; \
		fi; \
	done

# macOS frameworks are versioned bundles. The manifest must live in
# Versions/A/Resources/ so it is covered by the Versions/A/_CodeSignature
# seal; left at the bundle root it is unsealed and upload fails with 90238.
.PHONY: inject-privacy-manifest-macos
inject-privacy-manifest-macos:
	@fw=./build/Build/Products/Release/TailscaleKit.framework; \
	if [ -d "$$fw" ]; then \
		mkdir -p "$$fw/Versions/A/Resources"; \
		cp ./PrivacyInfo.xcprivacy "$$fw/Versions/A/Resources/PrivacyInfo.xcprivacy"; \
		rm -f "$$fw/Info.plist"; \
		codesign --force --sign - --timestamp=none "$$fw" >/dev/null 2>&1 || true; \
		echo "Injected PrivacyInfo.xcprivacy -> $$fw/Versions/A/Resources"; \
	fi

.PHONY: test
test: ## Run tests (macOS)
	@echo 
	@echo "::: Running tests for TailscaleKit :::"
	cd ../tstestcontrol && make all
	cd .. && make c-archive
	mkdir -p build
	xcodebuild build-for-testing -scheme TailscaleKitXCTests \
	 -derivedDataPath build \
	 -configuration Debug \
	 -quiet \
	 -destination 'platform=macOS,arch=arm64' \
	 CODE_SIGNING_ALLOWED=NO
	xcodebuild test-without-building  -scheme TailscaleKitXCTests \
	 -derivedDataPath build \
	 -configuration Debug \
	 -destination 'platform=macOS,arch=arm64' \
	 CODE_SIGNING_ALLOWED=NO

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
