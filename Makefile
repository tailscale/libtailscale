# Copyright (c) Tailscale Inc & AUTHORS
# SPDX-License-Identifier: BSD-3-Clause


libtailscale.a: 
	go build -buildmode=c-archive 

libtailscale_ios.a:
	GOOS=ios GOARCH=arm64 CGO_ENABLED=1 CC=$(PWD)/swift/script/clangwrap-ios.sh go build -v -ldflags -w -tags ios -o libtailscale_ios.a -buildmode=c-archive

libtailscale_ios_sim_arm64.a:
	GOOS=ios GOARCH=arm64 CGO_ENABLED=1 CC=$(PWD)/swift/script/clangwrap-ios-sim-arm.sh go build -v -ldflags -w -tags ios -o libtailscale_ios_sim_arm64.a -buildmode=c-archive

libtailscale_ios_sim_x86_64.a:
	GOOS=ios GOARCH=amd64 CGO_ENABLED=1 CC=$(PWD)/swift/script/clangwrap-ios-sim-x86.sh go build -v -ldflags -w -tags ios -o libtailscale_ios_sim_x86_64.a -buildmode=c-archive

.PHONY: c-archive-ios
c-archive-ios: libtailscale_ios.a  ## Builds libtailscale_ios.a for iOS (iOS SDK required)

.PHONY: c-archive-ios-sim
c-archive-ios-sim: libtailscale_ios_sim_arm64.a libtailscale_ios_sim_x86_64.a ## Builds a fat binary for iOS (iOS SDK required)
	lipo -create -output libtailscale_ios_sim.a libtailscale_ios_sim_x86_64.a libtailscale_ios_sim_arm64.a

.PHONY: c-archive 
c-archive: libtailscale.a  ## Builds libtailscale.a for the target platform

.PHONY: shared
shared: ## Builds libtailscale.so for the target platform
	go build -v -buildmode=c-shared

.PHONY: clean
clean: ## Clean up build artifacts
	rm -f libtailscale*.h
	rm -f libtailscale*.a

.PHONY: help
help: ## Show this help
	@echo "\nSpecify a command. The choices are:\n"
	@grep -hE '^[0-9a-zA-Z_-]+:.*?## .*$$' ${MAKEFILE_LIST} | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[0;36m%-12s\033[m %s\n", $$1, $$2}'
	@echo ""

.DEFAULT_GOAL := help
