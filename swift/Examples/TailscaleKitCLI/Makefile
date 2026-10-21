# Copyright (c) Tailscale Inc & AUTHORS
# SPDX-License-Identifier: BSD-3-Clause

.PHONY: spm-setup
spm-setup: ## Build the TailscaleKit artifact bundle this example depends on (Linux and macOS; see swift/README.md)
	@$(MAKE) -C ../.. spm-setup

.PHONY: help
help: ## Show this help
	@echo "\nSpecify a command. The choices are:\n"
	@grep -hE '^[0-9a-zA-Z_-]+:.*?## .*$$' ${MAKEFILE_LIST} | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[0;36m%-12s\033[m %s\n", $$1, $$2}'
	@echo ""

.DEFAULT_GOAL := help
