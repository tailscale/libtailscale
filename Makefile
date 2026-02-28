# Copyright (c) Tailscale Inc & AUTHORS
# SPDX-License-Identifier: BSD-3-Clause

# Detect GOOS if not set
ifeq ($(GOOS),)
	GOOS := $(shell go env GOOS)
endif

export CGO_ENABLED=1

# This should match the minimum target in the xCode project
# The wrapper lib currently requires features available in
# MacOS 15.0 (Sequoia)
MACOS_TARGET := 15.0

# Set macOS-specific flags for darwin builds
ifeq ($(GOOS),darwin)
	DARWIN_CGO_CFLAGS := -mmacos-version-min=$(MACOS_TARGET)
	DARWIN_CGO_LDFLAGS := -mmacos-version-min=$(MACOS_TARGET)
	DARWIN_DEPLOYMENT_TARGET := MACOSX_DEPLOYMENT_TARGET=$(MACOS_TARGET)
endif

libtailscale.so:
	$(DARWIN_DEPLOYMENT_TARGET) CGO_CFLAGS="$(CGO_CFLAGS) $(DARWIN_CGO_CFLAGS)" CGO_LDFLAGS="$(CGO_LDFLAGS) $(DARWIN_CGO_LDFLAGS)" go build -v -buildmode=c-shared -o $@

libtailscale.a:
	$(DARWIN_DEPLOYMENT_TARGET) CGO_CFLAGS="$(CGO_CFLAGS) $(DARWIN_CGO_CFLAGS)" CGO_LDFLAGS="$(CGO_LDFLAGS) $(DARWIN_CGO_LDFLAGS)" go build -buildmode=c-archive -o $@

libtailscale_ios.a:
	# TODO(raggi): setup a PREFIX in the libtailscale.a build, then delete these targets, the caller should be setting PREFIX and CC
	# that way the caller can also use the prefix, and not have to specialize target/link object names per build configuration.
	GOOS=ios GOARCH=arm64 CC=$(PWD)/swift/script/clangwrap-ios.sh go build -v -ldflags -w -tags ios -o $@ -buildmode=c-archive

libtailscale_ios_sim_arm64.a:
	GOOS=ios GOARCH=arm64 CC=$(PWD)/swift/script/clangwrap-ios-sim-arm.sh go build -v -ldflags -w -tags ios -o $@ -buildmode=c-archive

libtailscale_ios_sim_x86_64.a:
	GOOS=ios GOARCH=amd64 CC=$(PWD)/swift/script/clangwrap-ios-sim-x86.sh go build -v -ldflags -w -tags ios -o $@ -buildmode=c-archive

.PHONY: c-archive-ios
c-archive-ios: libtailscale_ios.a  ## Builds libtailscale_ios.a for iOS (iOS SDK required)

.PHONY: c-archive-ios-sim
c-archive-ios-sim: libtailscale_ios_sim_arm64.a libtailscale_ios_sim_x86_64.a ## Builds a fat binary for iOS (iOS SDK required)
	lipo -create -output libtailscale_ios_sim.a libtailscale_ios_sim_x86_64.a libtailscale_ios_sim_arm64.a

.PHONY: c-archive
c-archive: libtailscale.a  ## Builds libtailscale.a for the target platform

.PHONY: shared
shared: libtailscale.so ## Builds libtailscale.so for the target platform

.PHONY: test
test: test-go test-ruby test-swift ## Runs all tests available on the host platform

.PHONY: test-go
test-go: ## Runs Go and C integration tests
	go test -v ./...

.PHONY: test-ruby
test-ruby: ## Runs Ruby binding tests (requires ruby, bundler)
	@if command -v bundle >/dev/null 2>&1 && [ -f ruby/Gemfile ]; then \
		cd ruby && bundle exec rake test; \
	else \
		echo "skipping ruby tests: bundle not found"; \
	fi

.PHONY: test-swift
test-swift: ## Runs Swift binding tests (requires macOS, xcodebuild)
	@if [ "$(GOOS)" = "darwin" ] && command -v xcodebuild >/dev/null 2>&1; then \
		cd swift && $(MAKE) test; \
	else \
		echo "skipping swift tests: requires macOS with xcodebuild"; \
	fi

.PHONY: clean
clean: ## Clean up build artifacts
	rm -f libtailscale*.h
	rm -f libtailscale*.a
	rm -f libtailscale*.so


.PHONY: help
help: ## Show this help
	@echo "\nSpecify a command. The choices are:\n"
	@grep -hE '^[0-9a-zA-Z_-]+:.*?## .*$$' ${MAKEFILE_LIST} | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[0;36m%-12s\033[m %s\n", $$1, $$2}'
	@echo ""

.DEFAULT_GOAL := help
