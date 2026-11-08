# Copyright (c) Tailscale Inc & AUTHORS
# SPDX-License-Identifier: BSD-3-Clause

build:
	@git clone https://github.com/pybind/pybind11 || true
	cd .. && go build -buildmode=c-archive -o python/libtailscale.a github.com/tailscale/libtailscale
	pip install .

wheel:
	pip wheel .

clean:
	rm -rf pybind11/ libtailscale.a libtailscale.h dist/ build/ tailscale.egg-info/

.PHONY: build wheel clean
