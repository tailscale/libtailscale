# Copyright (c) Tailscale Inc & AUTHORS
# SPDX-License-Identifier: BSD-3-Clause

# Construct a source package by vendoring all source and packing it up into a
# tarball.

all: libtailscale.tar.zst

clean: 
	rm -rf libtailscale.tar.zst vendor

vendor: go.mod go.sum tailscale.go Makefile
	go mod vendor

libtailscale.tar.zst: vendor sourcepkg/Makefile sourcepkg/configure LICENSE tailscale.go go.mod go.sum
	tar --transform 's#^#libtailscale/#' --transform 's#sourcepkg/##' -acf $@ sourcepkg/Makefile sourcepkg/configure LICENSE tailscale.go go.mod go.sum vendor