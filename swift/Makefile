# Copyright (c) Tailscale Inc & AUTHORS
# SPDX-License-Identifier: BSD-3-Clause

## Prettifies xcode output for xcode tests using xcpretty, if it is installed
XCPRETTIFIER := xcpretty
ifeq (, $(shell which $(XCPRETTIFIER)))
        XCPRETTIFIER := cat
endif

OUTPUT_DIR=build

build:
	mkdir -p $(OUTPUT_DIR)
	xcodebuild build -scheme TailscaleKit -derivedDataPath $(OUTPUT_DIR) -configuration Release -destination 'generic/platform=macOS,arch=arm64' -destination 'generic/platform=iOS' | $(XCPRETTIFIER)

test:
	xcodebuild test -scheme TailscaleKitXCTests -derivedDataPath $(OUTPUT_DIR) -configuration Debug | $(XCPRETTIFIER)

clean:
	rm -rf $(OUTPUT_DIR)