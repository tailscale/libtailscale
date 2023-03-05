# Copyright (c) Tailscale Inc & AUTHORS
# SPDX-License-Identifier: BSD-3-Clause

build:
	@git clone https://github.com/pybind/pybind11 || true
	cd pybind11 && git checkout 3cc7e4258c15a6a19ba5e0b62a220b1a6196d4eb
	cd .. && go build -buildmode=c-archive -o python/libtailscale.a github.com/tailscale/libtailscale
	pip install .

wheel:
	pip wheel .

clean:
	rm -rf pybind11/ libtailscale.a libtailscale.h dist/ build/ tailscale.egg-info/

.PHONY: build wheel clean
